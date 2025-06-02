import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mnc_identifier_ocr/model/ocr_result_model.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class MncIdentifierOcr {
  static const MethodChannel _channel = MethodChannel('mnc_identifier_ocr');

  static Future<OcrResultModel> startCaptureKtp(
      {bool withFlash = false, bool cameraOnly = false}) async {
    try {
      final String? json = await _channel.invokeMethod('startCaptureKtp',
          {'withFlash': withFlash, 'cameraOnly': cameraOnly});
      if (json == null) {
        throw 'mnc-identifier-ocr: unexpected null data from scanner';
      }

      var result = OcrResultModel.fromJson(json);
      var imagePath = result.imagePath;
      if (imagePath != null) {
        final originalFile = File(imagePath);
        final bytes = await originalFile.readAsBytes();
        Uint8List? cropped = await autoCropFaceFromKTP(bytes);

        if (cropped != null) {
          final croppedFile = await saveImageToFile(cropped, originalFile, suffix: "_face");
          result.setFaceImagePath(croppedFile.path);
        } else {
          result.setFaceImagePath(null);
        }
      }
      
      return result;
    } catch (e) {
      rethrow;
    }
  }
  
  static Future<Uint8List?> autoCropFaceFromKTP(Uint8List ktpImageBytes) async {
    // Save Uint8List to temporary file
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/ktp.jpg');
    await tempFile.writeAsBytes(ktpImageBytes);

    // Load image into MLKit
    final inputImage = InputImage.fromFilePath(tempFile.path);
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: false,
      enableLandmarks: false,
    );
    final faceDetector = FaceDetector(options: options);
    final faces = await faceDetector.processImage(inputImage);
    faceDetector.close();

    // Decode image to crop it manually
    final originalImage = img.decodeImage(ktpImageBytes);
    if (originalImage == null || faces.isEmpty) return null;

    // Get first detected face
    final faceBox = faces.first.boundingBox;

    const int fixedWidth = 300;
    const int fixedHeight = 400;

    final centerX = faceBox.left + faceBox.width / 2;
    final centerY = faceBox.top + faceBox.height / 2;

    final left = (centerX - fixedWidth / 2).clamp(0, originalImage.width - fixedWidth).toInt();
    final top = (centerY - fixedHeight / 2).clamp(0, originalImage.height - fixedHeight).toInt();
    final width = fixedWidth.clamp(1, originalImage.width - left).toInt();
    final height = fixedHeight.clamp(1, originalImage.height - top).toInt();

    // Crop the image
    final cropped = img.copyCrop(originalImage, x: left, y: top, width: width, height: height);

    // Return new Uint8List (JPEG)
    return Uint8List.fromList(img.encodeJpg(cropped));
  }
    
  static Future<File> saveImageToFile(
    Uint8List imageBytes,
    File originalFile, {
      String suffix = '_new',
    }
  ) async {
    final originalName = originalFile.uri.pathSegments.last;
    final nameParts = originalName.split('.');
    final baseName = nameParts.sublist(0, nameParts.length - 1).join('.');
    final ext = nameParts.last;

    final newFileName = '$baseName$suffix.$ext';

    final targetDir = await getApplicationDocumentsDirectory();
    final newPath = '${targetDir.path}/$newFileName';

    final newFile = File(newPath);
    await newFile.writeAsBytes(imageBytes, flush: true);
    return newFile;
  }
}
