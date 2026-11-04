import 'package:material_ui/material_ui.dart';

/// A read-only field that looks like a text field and opens a picker
/// (date, time) when tapped.
class PickerField extends StatelessWidget {
  const PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.helperText,
    this.errorText,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final String? helperText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            helperText: helperText,
            errorText: errorText,
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
