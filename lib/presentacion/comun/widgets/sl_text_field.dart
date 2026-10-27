// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Campo de texto con etiqueta arriba y contraseña con mostrar/ocultar. No hace: no define reglas; recibe el validador.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/theme.dart';

/// Campo de texto estándar con etiqueta arriba (mejor legibilidad que el
/// label flotante bajo estrés) y soporte de contraseña con botón de mostrar.
///
/// ```dart
/// SlTextField(
///   label: 'Correo electrónico',
///   icon: Icons.mail_outline,
///   keyboardType: TextInputType.emailAddress,
///   validator: Validators.email,
/// )
/// ```
class SlTextField extends StatefulWidget {
  const SlTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.validator,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.maxLength,
    this.digitsOnly = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final String? Function(String?)? validator;

  /// Error que viene del ViewModel (la View no valida).
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscure;
  final int? maxLength;
  final bool digitsOnly;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<SlTextField> createState() => _SlTextFieldState();
}

class _SlTextFieldState extends State<SlTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: context.text.labelMedium?.copyWith(color: AppColors.textSecondary)),
        AppSpacing.gapXs,
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: _hidden,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          autofillHints: widget.autofillHints,
          style: context.text.bodyLarge,
          inputFormatters: [
            if (widget.digitsOnly) FilteringTextInputFormatter.digitsOnly,
            if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength),
          ],
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: widget.icon == null ? null : Icon(widget.icon),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
