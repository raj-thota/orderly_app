import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fluttercontactpicker/fluttercontactpicker.dart';

import 'capture_draft.dart';

/// Name + phone lifted from a device contact, ready to prefill the manual add
/// form. Either field may be null when the contact lacks it.
class ContactPick {
  const ContactPick({this.name, this.phone});
  final String? name;
  final String? phone;
}

/// Opens the OS contact picker and returns the chosen contact's name + phone.
/// Abstracted so widgets depend on the interface (not the native plugin) and it
/// can be faked in tests.
abstract class ContactsService {
  /// Returns the picked contact, or null when the user simply cancelled the
  /// picker. Throws [ContactPickException] when the picker itself failed
  /// (permission denied, plugin/OS error) so the UI can surface a real message
  /// instead of silently doing nothing.
  Future<ContactPick?> pickContact();
}

/// A real failure opening the OS contact picker — distinct from the user
/// cancelling. Carries the underlying error for logging, not for display.
class ContactPickException implements Exception {
  const ContactPickException(this.cause);
  final Object cause;
  @override
  String toString() => 'ContactPickException: $cause';
}

/// Pure mapping from the native picker's output to a [ContactPick]: trims the
/// name and normalizes the phone to digits. No plugin calls, so it is unit
/// tested directly.
ContactPick contactToPrefill(String? fullName, String? rawNumber) {
  final name = fullName?.trim();
  return ContactPick(
    name: (name == null || name.isEmpty) ? null : name,
    phone: CaptureDraft.normalizePhone(rawNumber),
  );
}

/// Real implementation backed by the native OS contact picker. Uses only the
/// single-contact picker (no address-book enumeration); on Android 11+ the
/// plugin requests READ_CONTACTS at runtime.
class DeviceContactsService implements ContactsService {
  /// A back-out from a real, on-screen picker takes a human at least a beat.
  /// Anything faster means the picker never actually opened.
  static const _minGenuineCancel = Duration(milliseconds: 700);

  @override
  Future<ContactPick?> pickContact() async {
    final sw = Stopwatch()..start();
    try {
      // Cap the wait so a picker that launches but never returns a result
      // (a silent native hang) surfaces as an error instead of a dead button.
      final contact = await FlutterContactPicker.pickPhoneContact()
          .timeout(const Duration(seconds: 60));
      return contactToPrefill(contact.fullName, contact.phoneNumber?.number);
    } on UserCancelledPickingException {
      // The plugin reports BOTH a genuine back-out AND a picker that failed to
      // open (native returns a null / "CANCELLED" result) as this same
      // exception. Distinguish by timing: an instant "cancel" means the picker
      // never appeared, so surface it instead of silently doing nothing.
      sw.stop();
      debugPrint('contact pick cancelled after ${sw.elapsedMilliseconds}ms');
      if (sw.elapsed < _minGenuineCancel) {
        throw const ContactPickException('picker did not open');
      }
      return null;
    } on TimeoutException catch (e) {
      debugPrint('contact pick timed out after ${sw.elapsedMilliseconds}ms');
      throw ContactPickException(e);
    } catch (e) {
      // Permission denied or a plugin/OS failure. Previously this was swallowed
      // identically to a cancel, so the button appeared dead. Surface it.
      debugPrint('contact pick failed after ${sw.elapsedMilliseconds}ms: $e');
      throw ContactPickException(e);
    }
  }
}
