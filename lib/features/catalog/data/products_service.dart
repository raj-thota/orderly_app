import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product.dart';
import 'signed_url_cache.dart';

class ProductsService {
  ProductsService({SupabaseClient? client, SignedUrlCache? urlCache})
      : _supabase = client ?? Supabase.instance.client,
        _urlCache = urlCache ?? SignedUrlCache();

  static const _bucket = 'product-images';
  static const _signedUrlTtlSeconds = 3600;

  final SupabaseClient _supabase;
  final SignedUrlCache _urlCache;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.id;
  }

  Future<List<Product>> fetchProducts() async {
    final rows = await _supabase
        .from('products')
        .select()
        .eq('user_id', _userId)
        .eq('active', true)
        .order('created_at', ascending: false);
    return rows.map<Product>((r) => Product.fromMap(r)).toList();
  }

  Future<Product> addProduct(Product product) async {
    final row = await _supabase
        .from('products')
        .insert({...product.toMap(), 'user_id': _userId})
        .select()
        .single();
    return Product.fromMap(row);
  }

  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async {
    final row = await _supabase
        .from('products')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId)
        .select()
        .single();
    return Product.fromMap(row);
  }

  /// Soft delete — orders may reference products, so rows are never removed.
  Future<void> archiveProduct(String id) async {
    await updateProduct(id, {'active': false});
  }

  /// Compresses and uploads one local photo; returns its storage path.
  Future<String> uploadImage(String localPath) async {
    final bytes = await _compress(localPath);
    final path =
        '$_userId/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.jpg';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<Uint8List> _compress(String localPath) async {
    final result = await FlutterImageCompress.compressWithFile(
      localPath,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      throw StateError('Could not read image at $localPath');
    }
    return result;
  }

  /// Short-lived signed URL for a private storage path (cached until near
  /// expiry — the bucket is private, paths are never served raw).
  Future<String> signedUrl(String path) async {
    final cached = _urlCache.get(path);
    if (cached != null) return cached;
    final url = await _supabase.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlTtlSeconds);
    _urlCache.put(path, url);
    return url;
  }
}
