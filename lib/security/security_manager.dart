import 'package:flutter/material.dart';
import 'dart:io';
import 'file_scan_service.dart';
import 'link_safety_service.dart';
import 'models/file_scan_result.dart';

class SecurityManager {
  static Future<void> openLink(BuildContext context, String url) async {
    await LinkSafetyService.openSafeUrl(context, url);
  }

  static Future<FileScanResult> scanAttachment(File file) async {
    return await FileScanService.scanFile(file);
  }
}
