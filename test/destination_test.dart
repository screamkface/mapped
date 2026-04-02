import 'package:flutter_test/flutter_test.dart';
import 'package:mapped_app/models/destination.dart';

void main() {
  test('builds full address and validates coordinates', () {
    final destination = Destination(
      id: '1',
      name: 'Sede',
      address: 'Via Roma 1',
      city: 'Roma',
      postalCode: '00100',
      notes: '',
      phone: '',
      photoPath: '/tmp/test.jpg',
      latitude: 41.9,
      longitude: 12.5,
      status: DestinationStatus.pending,
    );

    expect(destination.fullAddress, 'Via Roma 1, 00100 Roma');
    expect(destination.hasCoordinates, isTrue);
  });

  test('parses flexible CSV headers', () {
    final destination = Destination.fromCsvRow(<String, String>{
      'Nome': 'Cliente Test',
      'indirizzo': 'Via Milano 2',
      'città': 'Torino',
      'cap': '10100',
      'lat': '45,0703',
      'lng': '7,6869',
      'stato': 'completato',
    }, fallbackId: 'generated');

    expect(destination.name, 'Cliente Test');
    expect(destination.city, 'Torino');
    expect(destination.latitude, closeTo(45.0703, 0.0001));
    expect(destination.longitude, closeTo(7.6869, 0.0001));
    expect(destination.status, DestinationStatus.completed);
  });

  test('preserves custom fields from spreadsheet rows and json', () {
    final destination = Destination.fromCsvRow(<String, String>{
      'Nome': 'Cantiere Test',
      'indirizzo': 'Via Napoli 10',
      'città': 'Benevento',
      'Responsabile': 'Mario Rossi',
      'Codice Cantiere': 'BN-42',
      'Priorita': 'Alta',
      'telefono': '123456',
    }, fallbackId: 'generated');

    expect(destination.customFields, <String, String>{
      'Responsabile': 'Mario Rossi',
      'Codice Cantiere': 'BN-42',
      'Priorita': 'Alta',
    });

    final restored = Destination.fromJson(destination.toJson());
    expect(restored.customFields, destination.customFields);
  });

  test('preserves photo path in json serialization', () {
    final destination = Destination(
      id: 'photo-1',
      name: 'Con Foto',
      address: 'Via del Test 3',
      city: 'Benevento',
      postalCode: '82100',
      notes: '',
      phone: '',
      photoPath: '/tmp/destination_photos/photo_1.jpg',
      latitude: null,
      longitude: null,
      status: DestinationStatus.pending,
    );

    final restored = Destination.fromJson(destination.toJson());
    expect(restored.photoPath, destination.photoPath);
  });
}
