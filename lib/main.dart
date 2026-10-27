import 'package:flutter/material.dart';
import 'design.dart';
import 'features/workspace/driver_home.dart';
export 'features/workspace/driver_home.dart' show DriverHome;

const primary = HireDStyle.primary;
const bg = HireDStyle.canvas;
const ink = HireDStyle.ink;
const muted = HireDStyle.muted;
const border = HireDStyle.line;
const green = HireDStyle.success;
void main() => runApp(const HireDApp());

class HireDApp extends StatelessWidget {
  const HireDApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HireD Driver',
    debugShowCheckedModeBanner: false,
    theme: HireDStyle.theme(),
    home: const DriverHome(),
  );
}
