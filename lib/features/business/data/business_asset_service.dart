import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_profile_service.dart';

/// Picks an image, compresses it, uploads to the `business-assets` bucket and
/// returns the public URL. Returns null if the user cancels the picker.
class BusinessAssetService {
  BusinessAssetService({ImagePicker? picker, SupabaseClient? client})
      : _picker = picker ?? ImagePicker(),
        _supabase = client ?? Supabase.instance.client;

  final ImagePicker _picker;
  final SupabaseClient _supabase;

  Future<String?> pickAndUpload({required String kind}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
    );
    if (picked == null) return null;

    final compressed = await FlutterImageCompress.compressWithFile(
      picked.path,
      quality: 70,
      minWidth: 512,
    );
    final bytes = compressed ?? await File(picked.path).readAsBytes();

    final path = BusinessProfileService.assetStoragePath(
      userId: user.id,
      kind: kind,
      extension: 'jpg',
    );
    await _supabase.storage.from('business-assets').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _supabase.storage.from('business-assets').getPublicUrl(path);
  }
}
