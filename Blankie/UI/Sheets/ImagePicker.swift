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
        print("🎨 ImagePicker: User selected an image")
        if let image = info[.originalImage] as? UIImage {
          print("🎨 ImagePicker: Original image size: \(image.size)")
          // Crop to square and convert to data
          let squareImage = cropToSquare(image: image)
          let imageData = squareImage.jpegData(compressionQuality: 0.8)
          print("🎨 ImagePicker: Cropped to square, data size: \(imageData?.count ?? 0) bytes")
          parent.imageData = imageData
          print("🎨 ImagePicker: Set parent.imageData")
        } else {
          print("❌ ImagePicker: Could not get original image from info")
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
