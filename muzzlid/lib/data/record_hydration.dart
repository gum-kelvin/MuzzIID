import 'dart:isolate';
import '../domain/register.dart';

Future<List<Animal>> hydrateAnimals(List<dynamic> records) => Isolate.run(() =>
    records.map((j) => Animal.fromJson(Map<String, dynamic>.from(j))).toList());
