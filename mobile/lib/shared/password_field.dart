import 'package:flutter/material.dart';

/// Every password box in ChoreQuest (PA-4): hidden as it is typed, with an
/// eye to show it, so a parent can check a long password on a small
/// keyboard before sending it.
///
/// Works inside a [Form], where [validator] runs, or on its own.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.labelText = 'Password',
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.newPassword = false,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool autofocus;

  /// A password being chosen rather than typed from memory, so a password
  /// manager offers to make and save one.
  final bool newPassword;

  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_shown,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _shown ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _shown = !_shown),
          icon: Icon(_shown ? Icons.visibility_off_rounded : Icons.visibility_rounded),
        ),
      ),
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
