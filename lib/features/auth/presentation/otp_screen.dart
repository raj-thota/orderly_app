import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import '../controller/auth_controller.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;

  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController otpController = TextEditingController();

  void verifyOtp() async {
    final otp = otpController.text.trim();

    if (otp.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid OTP")));
      return;
    }

    final success = await ref
        .read(authProvider.notifier)
        .verifyOtp(widget.phone, otp);

    if (!mounted) return;

    if (success) {
      ref.read(eventServiceProvider).track('signup_completed');
      // Pop back to RootGate (app root), which reactively routes to business
      // setup for new users or the main shell for returning ones. Pushing
      // MainScreen directly here skipped the setup gate for first-time users.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
    }
  }

  void resendOtp() async {
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not resend OTP")));
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("OTP resent")));
  }

  @override
  void dispose() {
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Verify"),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              /// 🔥 ICON
              const Icon(
                Icons.sms_outlined,
                size: 60,
                color: AppColors.primary,
              ),

              const SizedBox(height: 20),

              /// 🔥 TITLE
              const Text(
                "Verify your number",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              /// 🔥 SUBTEXT
              Text(
                "We’ve sent an OTP to +91 ${widget.phone}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 30),

              /// 🔢 OTP INPUT
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 20,
                    letterSpacing: 6,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    counterText: "",
                    hintText: "••••••",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              /// 🔁 RESEND
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Didn’t receive OTP?",
                    style: TextStyle(color: Colors.grey),
                  ),
                  TextButton(onPressed: resendOtp, child: const Text("Resend")),
                ],
              ),

              const SizedBox(height: 20),

              /// 🚀 VERIFY BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.isLoading ? null : verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: state.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Verify & Continue",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              /// 🔒 TRUST
              const Text(
                "Your number is safe with us",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),

              const Spacer(),

              /// 🔥 FOOTER
              const Text(
                "Logging you into your business workspace",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
