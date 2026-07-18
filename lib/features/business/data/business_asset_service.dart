import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_profile_service.dart';

/// Picks an image, compresses it, and uploads it. Logos go to the public
/// `business-assets` bucket (they appear on customer-facing invoices) and a
/// public URL is returned. Signatures are sensitive, so they go to the private
/// `business-signatures` bucket and a time-limited signed URL is returned.
/// Returns null if the user cancels the picker.
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

    final bucket =
        kind == 'signature' ? 'business-signatures' : 'business-assets';
    final path = BusinessProfileService.assetStoragePath(
      userId: user.id,
      kind: kind,
      extension: 'jpg',
    );
    final storage = _supabase.storage.from(bucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    if (bucket == 'business-signatures') {
      // Private bucket: hand back a 1-year signed URL. Re-sign server-side when
      // rendering the signature on an invoice.
      return storage.createSignedUrl(path, 60 * 60 * 24 * 365);
    }
    return storage.getPublicUrl(path);
  }
}
