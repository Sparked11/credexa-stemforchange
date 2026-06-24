import Flutter
import UIKit
import ARKit
import SceneKit
import CoreImage
import Vision
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
//  TrustLensARViewFactory
//  Registered in AppDelegate so Flutter can create the view by type-id.
// ─────────────────────────────────────────────────────────────────────────────

@objc class TrustLensARViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    @objc init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return TrustLensARPlatformView(frame: frame, viewId: viewId, messenger: messenger)
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TrustLensARPlatformView  (thin wrapper required by the protocol)
// ─────────────────────────────────────────────────────────────────────────────

class TrustLensARPlatformView: NSObject, FlutterPlatformView {
    private let arScene: TrustLensARScene

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        arScene = TrustLensARScene(frame: frame, viewId: viewId, messenger: messenger)
        super.init()
    }

    func view() -> UIView { return arScene }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TrustLensARScene  — the real ARSCNView with all logic
// ─────────────────────────────────────────────────────────────────────────────

class TrustLensARScene: ARSCNView {
    private let channel: FlutterMethodChannel
    private var anchorNodes: [String: SCNNode] = [:]
    private let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
    private var usingFront = false   // false = rear world-tracking, true = front face-tracking

    // Portrait orientation for the captured frame depends on which camera is active.
    // Rear → 90° CW (.right); front → mirrored (.leftMirrored).
    private var captureOrientation: CGImagePropertyOrientation {
        usingFront ? .leftMirrored : .right
    }

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "credexa/trust_lens_ar/\(viewId)",
            binaryMessenger: messenger
        )
        super.init(frame: frame, options: nil)
        setupAR()
        setupChannel()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        session.pause()
        channel.setMethodCallHandler(nil)
    }

    // ── AR Session ──────────────────────────────────────────────────────────

    private func setupAR() {
        guard ARWorldTrackingConfiguration.isSupported else {
            // Simulator or device without ARKit — show a plain black view.
            backgroundColor = .black
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // Use LiDAR mesh on Pro devices for better depth (iOS 13.4+ only)
        if #available(iOS 13.4, *),
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        autoenablesDefaultLighting = true
        automaticallyUpdatesLighting = true
        antialiasingMode = .multisampling4X
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // ── MethodChannel ───────────────────────────────────────────────────────

    private func setupChannel() {
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "DISPOSED", message: nil, details: nil))
                return
            }
            DispatchQueue.main.async {
                switch call.method {
                case "snapshot":     self.doSnapshot(result)
                case "raycast":      self.doRaycast(call.arguments, result)
                case "addNode":      self.doAddNode(call.arguments, result)
                case "removeNode":   self.doRemoveNode(call.arguments, result)
                case "clearNodes":   self.doClearNodes(result)
                case "getProj":      self.doGetProjection(call.arguments, result)
                case "setTorch":     self.doSetTorch(call.arguments, result)
                case "detectFaces":  self.doDetectFaces(result)
                case "flipCamera":   self.doFlipCamera(call.arguments, result)
                default:             result(FlutterMethodNotImplemented)
                }
            }
        }
    }

    // ── snapshot ─────────────────────────────────────────────────────────────
    // Returns the raw ARKit camera frame as a portrait-oriented JPEG plus its
    // pixel dimensions so Dart can map ML Kit block rects to screen coords.

    private func doSnapshot(_ result: @escaping FlutterResult) {
        guard let frame = session.currentFrame else {
            result(FlutterError(code: "NO_FRAME", message: "No ARFrame yet", details: nil))
            return
        }

        let pb = frame.capturedImage               // YCbCr 420f, landscape-left
        var ci = CIImage(cvPixelBuffer: pb)

        // Rotate to portrait per the active camera (rear .right / front .leftMirrored).
        ci = ci.oriented(captureOrientation)

        guard let cg = ciCtx.createCGImage(ci, from: ci.extent) else {
            result(FlutterError(code: "CI_FAIL", message: "CIContext render failed", details: nil))
            return
        }

        let ui = UIImage(cgImage: cg)
        guard let jpeg = ui.jpegData(compressionQuality: 0.82) else {
            result(FlutterError(code: "JPEG_FAIL", message: nil, details: nil))
            return
        }

        result([
            "jpeg":   FlutterStandardTypedData(bytes: jpeg),
            "width":  Int(cg.width),
            "height": Int(cg.height),
        ])
    }

    // ── raycast ──────────────────────────────────────────────────────────────
    // Input: { x: 0.0–1.0, y: 0.0–1.0 } normalised screen coordinates.
    // Returns: { x, y, z } world position or nil if no surface is hit.
    // Falls back to a point 0.35 m ahead of the camera when ARKit misses.

    private func doRaycast(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any],
              let nx = d["x"] as? Double,
              let ny = d["y"] as? Double else {
            result(FlutterError(code: "BAD_ARGS", message: "Expected {x,y}", details: nil))
            return
        }

        let pt = CGPoint(x: nx * Double(bounds.width), y: ny * Double(bounds.height))

        if let q = raycastQuery(from: pt, allowing: .estimatedPlane, alignment: .any) {
            let hits = session.raycast(q)
            if let h = hits.first {
                let c = h.worldTransform.columns.3
                result(["x": c.x, "y": c.y, "z": c.z])
                return
            }
        }

        // Fallback: place anchor 0.35 m in front of the camera
        if let cam = session.currentFrame?.camera.transform {
            let fwd = -simd_float3(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
            let pos =  simd_float3(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            let wp  = pos + fwd * 0.35
            result(["x": wp.x, "y": wp.y, "z": wp.z])
        } else {
            result(nil)
        }
    }

    // ── addNode ──────────────────────────────────────────────────────────────
    // Places a glowing sphere anchor at the given world coordinates.
    // Args: { id: String, x, y, z: Double, color: Int (0xRRGGBB) }

    private func doAddNode(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any],
              let id  = d["id"] as? String,
              let wx  = d["x"]  as? Double,
              let wy  = d["y"]  as? Double,
              let wz  = d["z"]  as? Double,
              let hex = d["color"] as? Int else {
            result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
            return
        }

        anchorNodes[id]?.removeFromParentNode()

        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        let color = UIColor(red: r, green: g, blue: b, alpha: 1)

        // Inner sphere
        let sphere = SCNSphere(radius: 0.014)
        let mat = SCNMaterial()
        mat.diffuse.contents  = color.withAlphaComponent(0.90)
        mat.emission.contents = color.withAlphaComponent(0.55)
        mat.lightingModel = .constant
        sphere.materials = [mat]
        let sphereNode = SCNNode(geometry: sphere)

        // Outer halo ring
        let torus = SCNTorus(ringRadius: 0.022, pipeRadius: 0.003)
        let torusMat = SCNMaterial()
        torusMat.diffuse.contents  = color.withAlphaComponent(0.40)
        torusMat.emission.contents = color.withAlphaComponent(0.30)
        torusMat.lightingModel = .constant
        torus.materials = [torusMat]
        let torusNode = SCNNode(geometry: torus)
        torusNode.eulerAngles.x = .pi / 2   // face camera-ish

        // Pulse animation on the sphere
        let pulse = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.scale(to: 1.35, duration: 0.75),
            SCNAction.scale(to: 1.00, duration: 0.75),
        ]))
        sphereNode.runAction(pulse)

        // Slow rotation on the ring
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 4))
        torusNode.runAction(spin)

        let container = SCNNode()
        container.addChildNode(sphereNode)
        container.addChildNode(torusNode)
        container.position = SCNVector3(wx, wy, wz)

        scene.rootNode.addChildNode(container)
        anchorNodes[id] = container
        result(nil)
    }

    // ── removeNode / clearNodes ──────────────────────────────────────────────

    private func doRemoveNode(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any], let id = d["id"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
            return
        }
        anchorNodes[id]?.removeFromParentNode()
        anchorNodes.removeValue(forKey: id)
        result(nil)
    }

    private func doClearNodes(_ result: @escaping FlutterResult) {
        anchorNodes.values.forEach { $0.removeFromParentNode() }
        anchorNodes.removeAll()
        result(nil)
    }

    // ── getProjection ────────────────────────────────────────────────────────
    // Returns the 2-D screen point (x, y) of the named anchor node so Flutter
    // can position an overlay chip directly over the 3-D world anchor.

    private func doGetProjection(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any],
              let id = d["id"] as? String,
              let node = anchorNodes[id] else {
            result(nil); return
        }
        let sp = projectPoint(node.worldPosition)
        result(["x": sp.x, "y": sp.y])
    }

    // ── setTorch ─────────────────────────────────────────────────────────────
    // Turns the rear torch on/off via AVCaptureDevice (ARKit shares the camera).

    private func doSetTorch(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any], let on = d["on"] as? Bool else {
            result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
            return
        }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            result(nil); return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch { /* torch not available — ignore */ }
        result(nil)
    }

    // ── flipCamera ───────────────────────────────────────────────────────────
    // Switches the ARSession between rear world-tracking and front face-tracking.
    // Args: { front: Bool }.  Returns true on success, false if unsupported.

    private func doFlipCamera(_ args: Any?, _ result: @escaping FlutterResult) {
        guard let d = args as? [String: Any], let front = d["front"] as? Bool else {
            result(false); return
        }

        if front {
            guard ARFaceTrackingConfiguration.isSupported else {
                result(false); return
            }
            let cfg = ARFaceTrackingConfiguration()
            cfg.isLightEstimationEnabled = true
            session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
            usingFront = true
        } else {
            let cfg = ARWorldTrackingConfiguration()
            cfg.planeDetection = [.horizontal, .vertical]
            if #available(iOS 13.4, *),
               ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                cfg.sceneReconstruction = .mesh
            }
            session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
            usingFront = false
        }

        // World anchors are invalid after a camera switch — drop the 3-D nodes.
        anchorNodes.values.forEach { $0.removeFromParentNode() }
        anchorNodes.removeAll()
        result(true)
    }

    // ── detectFaces ──────────────────────────────────────────────────────────
    // Runs VNDetectFaceRectanglesRequest on the current ARKit camera frame.
    // Returns an array of { x, y, w, h } dicts in top-left-origin normalized
    // portrait-image coordinates (0.0–1.0), ready for direct screen scaling.

    private func doDetectFaces(_ result: @escaping FlutterResult) {
        guard let frame = session.currentFrame else { result([]); return }

        let ci = CIImage(cvPixelBuffer: frame.capturedImage).oriented(captureOrientation)
        guard let cg = ciCtx.createCGImage(ci, from: ci.extent) else { result([]); return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let boxes = (request.results ?? []).map { obs -> [String: Any] in
                    let box = obs.boundingBox
                    // Vision uses bottom-left origin → flip Y to top-left
                    return [
                        "x": Double(box.minX),
                        "y": Double(1.0 - box.maxY),
                        "w": Double(box.width),
                        "h": Double(box.height),
                    ]
                }
                // FlutterResult must be called on the main thread
                DispatchQueue.main.async { result(boxes) }
            } catch {
                DispatchQueue.main.async { result([]) }
            }
        }
    }
}
