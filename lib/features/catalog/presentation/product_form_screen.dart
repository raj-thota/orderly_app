import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';

import '../controller/products_provider.dart';
import '../data/product.dart';
import '../widgets/product_image.dart';

const _maxPhotos = 5;

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing});

  /// When set, the form edits this product instead of creating a new one.
  final Product? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _qty;

  late bool _isUnique;
  late List<String> _existingImages; // storage paths already uploaded
  final List<XFile> _newPhotos = []; // picked locally, uploaded on save
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  int get _photoCount => _existingImages.length + _newPhotos.length;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
      text: p == null
          ? ''
          : (p.price == p.price.roundToDouble()
              ? p.price.toStringAsFixed(0)
              : p.price.toString()),
    );
    _description = TextEditingController(text: p?.description ?? '');
    _qty = TextEditingController(text: (p?.qtyOnHand ?? 1).toString());
    _isUnique = p?.isUnique ?? true;
    _existingImages = List.of(p?.images ?? const []);
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _description, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 92);
      if (file != null && mounted) {
        setState(() => _newPhotos.add(file));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera or gallery.')),
      );
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final controller = ref.read(productsControllerProvider.notifier);
    final service = ref.read(productsServiceProvider);

    try {
      final uploaded = <String>[];
      for (final photo in _newPhotos) {
        uploaded.add(await service.uploadImage(photo.path));
      }
      final images = [..._existingImages, ...uploaded];

      final name = _name.text.trim();
      final price = double.parse(_price.text.trim());
      final description =
          _description.text.trim().isEmpty ? null : _description.text.trim();
      final qty = _isUnique ? 0 : int.parse(_qty.text.trim());

      if (_isEdit) {
        await controller.updateProduct(widget.existing!.id!, {
          'name': name,
          'price': price,
          'description': description,
          'is_unique': _isUnique,
          'qty_on_hand': qty,
          'images': images,
        });
      } else {
        await controller.addProduct(Product(
          name: name,
          price: price,
          description: description,
          isUnique: _isUnique,
          qtyOnHand: qty,
          images: images,
        ));
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Piece updated' : 'Added to catalog')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit piece' : 'Add piece'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _photoStrip(),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('Price (₹)'),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return 'Enter a valid price';
                if (parsed < 0) return 'Price cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Description (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SwitchListTile(
              value: _isUnique,
              onChanged: (v) => setState(() => _isUnique = v),
              activeTrackColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'One-of-a-kind piece',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Single item that can be booked and sold once.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            if (!_isUnique) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: _decoration('Quantity in stock'),
                validator: (v) {
                  if (_isUnique) return null;
                  final parsed = int.tryParse((v ?? '').trim());
                  if (parsed == null) return 'Enter a whole number';
                  if (parsed < 0) return 'Quantity cannot be negative';
                  return null;
                },
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: _isEdit ? 'Save changes' : 'Add to catalog',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      );

  Widget _photoStrip() {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _existingImages.length; i++)
            _thumb(
              child: ProductImage(path: _existingImages[i], iconSize: 22),
              onRemove: () => setState(() => _existingImages.removeAt(i)),
            ),
          for (var i = 0; i < _newPhotos.length; i++)
            _thumb(
              child: Image.file(File(_newPhotos[i].path), fit: BoxFit.cover),
              onRemove: () => setState(() => _newPhotos.removeAt(i)),
            ),
          if (_photoCount < _maxPhotos)
            GestureDetector(
              onTap: _showPhotoSourceSheet,
              child: Container(
                width: 96,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
                    SizedBox(height: 4),
                    Text(
                      'Add photo',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: child,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
