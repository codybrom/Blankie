//
//  ImagePicker.swift
//  Blankie
//
//  Created by Cody Bromley on 6/16/25.
//

import SwiftUI

#if os(iOS)
  import UIKit

  // MARK: - Supporting Views

  struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.delegate = context.coordinator
      picker.sourceType = .photoLibrary
      return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
      let parent: ImagePicker

      init(_ parent: ImagePicker) {
        self.parent = parent
      }

      func imagePickerController(
        _: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        debugLog("ImagePicker: User selected an image", .ui)
        if let image = info[.originalImage] as? UIImage {
          debugLog("ImagePicker: Original image size: \(image.size)", .ui)
          // Crop to square and convert to data
          let squareImage = cropToSquare(image: image)
          let imageData = squareImage.jpegData(compressionQuality: 0.8)
          debugLog("ImagePicker: Cropped to square, data size: \(imageData?.count ?? 0) bytes", .ui)
          parent.imageData = imageData
          debugLog("ImagePicker: Set parent.imageData", .ui)
        } else {
          logError("ImagePicker: Could not get original image from info", .ui)
        }
        parent.dismiss()
      }

      func imagePickerControllerDidCancel(_: UIImagePickerController) {
        parent.dismiss()
      }

      private func cropToSquare(image: UIImage) -> UIImage {
        let size = min(image.size.width, image.size.height)
        let origin = CGPoint(
          x: (image.size.width - size) / 2,
          y: (image.size.height - size) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: size, height: size))

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
      }
    }
  }
#endif
