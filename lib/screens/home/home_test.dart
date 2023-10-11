import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'dart:math' as Math;
import 'package:http/http.dart' as http;
import 'package:country_flags/country_flags.dart';
import 'dart:convert';
import 'package:geocoding/geocoding.dart';

import 'package:remitbee/constants.dart';

class HomeTestScreen extends StatefulWidget {
  const HomeTestScreen({Key? key}) : super(key: key);

  @override
  State<HomeTestScreen> createState() => HomeTestScreenState();
}

class HomeTestScreenState extends State<HomeTestScreen> {
  GoogleMapController? mapController;
  final LatLng _center =
      const LatLng(45.521563, -122.677433); // Set your desired coordinates
  loc.Location location = new loc.Location();
  loc.LocationData? currentLocation;
  Set<Circle> circles = Set.from([]);
  double selectedRadius = 1.0; // Default radius in kilometers
  Set<Marker> markers = {};
  bool isOpen = false;
  TextEditingController currencyController = TextEditingController();
  String selectedCurrency = "INR";
  int? selectedCurrencyRate;
  double? covertedRate;
  bool isShopCardOpen = false;
  String shopName = '';
  double shopRate = 0.0;
  double shopScore = 0.0;
  String currentPlace = '';
  List<String> isoValues = [];
  http.Client client = http.Client();
  late Future _dataFuture;
  List<Map<String, dynamic>> shops = [
    {
      'name': 'Sampath Bank Plc, Nawala Koswatta Branch',
      'rate': 15,
      'location': [6.894923, 79.887876], // Replace with actual coordinates
      'score': 26.78
    },
    {
      'name': 'The Sovereign ***',
      'rate': 25,
      'location': [6.899408, 79.893693], // Replace with actual coordinates
      'score': 0.2
    },
    {
      'name': 'Zylan Luxury Villa ****',
      'rate': 23,
      'location': [6.910101, 79.894931], // Replace with actual coordinates
      'score': 0.19
    },
    {
      'name': 'Hotel Janaki ***',
      'rate': 20,
      'location': [6.888039, 79.887449], // Replace with actual coordinates
      'score': 0.16
    }
  ];

  void _onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    loc.LocationData currentLocation = await location.getLocation();
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(currentLocation.latitude!, currentLocation.longitude!),
          zoom: 14.0,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    currencyController.text = '1';
    _getCurrentUserLocation();
    _dataFuture =
        Future.wait([fetchExchangeRate(selectedCurrency), fetchCurrencies()]);
    currencyController.addListener(handleText);
  }

  void handleText() {
    if (currencyController.text.isEmpty) {
      currencyController.text = '1';
    }
  }

  void _updatePlaceName() async {
    List<Placemark> placemarks = await placemarkFromCoordinates(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
    );
    Placemark place = placemarks[0];

    setState(() {
      currentPlace = "${place.locality}, ${place.country}";
    });
  }

  _getCurrentUserLocation() async {
    bool _serviceEnabled;
    loc.PermissionStatus _permissionGranted;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    location.onLocationChanged.listen((loc.LocationData currentLocation) {
      // if (mapController != null) {
      //   mapController!.animateCamera(
      //     CameraUpdate.newCameraPosition(
      //       CameraPosition(
      //         target:
      //             LatLng(currentLocation.latitude!, currentLocation.longitude!),
      //         zoom: 14.0,
      //       ),
      //     ),
      //   );
      // }

      setState(() {
        this.currentLocation = currentLocation;
        _updateMarkers(); // Update the markers when the current location changes
        circles.add(
          Circle(
            circleId: CircleId('Search Radius'),
            center:
                LatLng(currentLocation.latitude!, currentLocation.longitude!),
            radius: selectedRadius * 1000,
            fillColor: Colors.blue.withOpacity(0.1),
            strokeColor: Colors.blue,
            strokeWidth: 1,
          ),
        );
        _updatePlaceName();
      });
    });
  }

  double _calculateDistance(LatLng location1, LatLng location2) {
    final p = Math.pi / 180;
    final a = 0.5 -
        Math.cos((location2.latitude - location1.latitude) * p) / 2 +
        Math.cos(location1.latitude * p) *
            Math.cos(location2.latitude * p) *
            (1 - Math.cos((location2.longitude - location1.longitude) * p)) /
            2;
    return 12742 * Math.asin(Math.sqrt(a)); // 2 * R; R = 6371 km
  }

  List<Map<String, dynamic>> _filterShopsByRadius(
      List<Map<String, dynamic>> shops,
      double radiusInKm,
      LatLng userLocation) {
    return shops
        .where((shop) =>
            _calculateDistance(
                LatLng(userLocation.latitude, userLocation.longitude),
                LatLng(shop['location'][0], shop['location'][1])) <=
            radiusInKm)
        .toList();
  }

  List<Marker> _createMarkers(
      List<Map<String, dynamic>> shops, LatLng userLocation) {
    List<Map<String, dynamic>> filteredShops =
        _filterShopsByRadius(shops, selectedRadius, userLocation);
    return filteredShops.map<Marker>((shop) {
      return Marker(
        markerId: MarkerId(shop['name']),
        position: LatLng(
          shop['location'][0],
          shop['location'][1],
        ),
        onTap: () {},
        infoWindow: InfoWindow(
          onTap: () {
            setState(() {
              isShopCardOpen = !isShopCardOpen;
            });
          },
          title: shop['name'],
          snippet: 'Rate: ${shop['rate']}',
        ),
      );
    }).toList();
  }

  void _updateMarkers() {
    if (currentLocation != null) {
      var newMarkers = _createMarkers(
        shops,
        LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      );
      setState(() {
        markers.clear();
        markers.addAll(newMarkers);
      });
    }
  }

  Future<void> fetchExchangeRate(String from) async {
    final response = await http.post(
      Uri.parse('https://api.wisecapitals.com/cronjobs/fetchXERate'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization':
            'Basic ' + base64Encode(utf8.encode('ronak:password123test')),
      },
      body: jsonEncode(<String, String>{
        'from': from,
        'to': 'LKR',
      }),
    );

    if (response.statusCode == 200) {
      var exchangeRate = jsonDecode(response.body);
      // double forwardRate = exchangeRate['forward']['LKR'];
      // print('Exchange rate: $forwardRate');
      double forwardRate = exchangeRate['forward']['LKR'].toDouble();
      int roundedForwardRate = forwardRate.round();
      selectedCurrencyRate = roundedForwardRate;
    } else {
      // If the server did not return a 200 OK response, throw an exception.
      throw Exception('Failed to load exchange rate');
    }
    calculateCurrencyRate();
  }

  Future<void> fetchCurrencies() async {
    String username = 'infozenit28348152';
    String password = 'nfabehsuhv9kif5ji7c744dlou';
    String basicAuth =
        'Basic ' + base64Encode(utf8.encode('$username:$password'));
    final response = await http.get(
      Uri.parse(
          'https://xecdapi.xe.com/v1/currencies.json'), // Replace with your API URL
      headers: <String, String>{
        'authorization': basicAuth,
      },
    );

    if (response.statusCode == 200) {
      // If the server returns a 200 OK response,
      // then parse the JSON.
      Map<String, dynamic> jsonData = jsonDecode(response.body);

      // Assuming the currencies are in a list under a property 'currencies'
      List<dynamic> currencies = jsonData['currencies'];

      // Extract the 'iso' property of each currency and store in a list
      isoValues = currencies
          .map<String>((currency) => currency['iso'] as String)
          .toList();
      print(isoValues);
    } else {
      // If the server returns an unsuccessful response code,
      // then throw an exception.
      throw Exception('Failed to load data');
    }
  }

  calculateCurrencyRate() {
    double? currency = double.tryParse(currencyController.text);
    covertedRate = 0;
    if (currency != null) {
      double? rate = selectedCurrencyRate?.toDouble();
      if (rate != null) {
        double? convertedRate = currency * rate;
        setState(() {
          covertedRate = convertedRate;
        });
      }
    }
  }

  Widget buildSelectCurrency(String newSelectedCurrency, String countryCode) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCurrency = newSelectedCurrency;
          fetchExchangeRate(selectedCurrency);
          isOpen = false;
        });
      },
      child: Container(
        height: 35,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100.0),
          color: selectedCurrency == newSelectedCurrency
              ? primary
              : primary.withOpacity(0.80),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CountryFlag.fromCountryCode(
              countryCode,
              height: 20,
              width: 20,
              borderRadius: 10,
            ),
            Text(
              newSelectedCurrency,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width =
        MediaQuery.of(context).size.width - MediaQuery.of(context).padding.left;
    return FutureBuilder(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator(); // Loading indicator
        } else {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}'); // Error handling
          } else {
            return MaterialApp(
              home: Scaffold(
                body: SafeArea(
                  child: Scaffold(
                    body: Stack(
                      children: <Widget>[
                        GoogleMap(
                          onMapCreated: _onMapCreated,
                          initialCameraPosition: CameraPosition(
                            target: _center,
                            zoom: 11.0,
                          ),
                          myLocationButtonEnabled: true,
                          myLocationEnabled: true,
                          zoomControlsEnabled: false,
                          circles: circles,
                          markers: markers,
                        ),
                        Positioned(
                          bottom: 50,
                          right: 15,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: selectedRadius,
                              activeColor: primary,
                              onChanged: (value) {
                                setState(() {
                                  selectedRadius = value;
                                  circles.clear();
                                  circles.add(
                                    Circle(
                                      circleId: CircleId('Search Radius'),
                                      center: LatLng(currentLocation!.latitude!,
                                          currentLocation!.longitude!),
                                      radius: selectedRadius *
                                          1000, // Convert radius to meters
                                      fillColor: Colors.blue.withOpacity(0.1),
                                      strokeColor: Colors.blue,
                                      strokeWidth: 1,
                                    ),
                                  );
                                  _updateMarkers();
                                });
                              },
                              min: 1.0,
                              max: 5.0,
                              divisions: 5,
                              label: '${selectedRadius.round()}km',
                            ),
                          ),
                        ),
                        Positioned(
                          top: 15.0,
                          left: 15.0,
                          right: 15.0,
                          child: Container(
                            height: 50,
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(100.0),
                              color: primary.withOpacity(0.5),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      isOpen = !isOpen;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    height: 35,
                                    width: width * 0.375,
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(100.0),
                                      color: primary,
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 1,
                                              child: TextField(
                                                cursorColor: Colors.white,
                                                cursorOpacityAnimates: true,
                                                controller: currencyController,
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly
                                                ],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontFamily: 'Inter',
                                                ),
                                                onSubmitted: (value) {
                                                  calculateCurrencyRate();
                                                },
                                                textAlign: TextAlign.left,
                                                decoration: InputDecoration(
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  border: InputBorder.none,
                                                  contentPadding:
                                                      const EdgeInsets.all(0),
                                                  isDense: true,
                                                  hintStyle: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.75),
                                                    fontWeight: FontWeight.w400,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Text(
                                              selectedCurrency,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontFamily: 'Inter',
                                              ),
                                            ),
                                            const SizedBox(
                                              width: 20,
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          top: 11,
                                          right: 0,
                                          child: AnimatedRotation(
                                            duration: const Duration(
                                                milliseconds: 400),
                                            curve: Curves.easeInOut,
                                            turns: isOpen ? -0.25 : 0.25,
                                            child: const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 12.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 50,
                                  child: Icon(
                                    Icons.compare_arrows_rounded,
                                    color: primary,
                                    size: 30,
                                  ),
                                ),
                                Container(
                                  height: 35,
                                  width: width * 0.375,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100.0),
                                    color: primary,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${covertedRate.toString()} LKR',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 75,
                          left: 25,
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: AnimatedContainer(
                              height: isOpen ? 200 : 0,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                              width: width * 0.375,
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  children: [
                                    buildSelectCurrency(
                                      'CAD',
                                      'CA',
                                    ),
                                    const SizedBox(
                                      height: 5,
                                    ),
                                    buildSelectCurrency(
                                      'INR',
                                      'IN',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 15.0,
                          left: 15.0,
                          right: 15.0,
                          child: GestureDetector(
                            onTap: () {},
                            child: Container(
                              height: 40,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100.0),
                                color: primary,
                              ),
                              child: Center(
                                child: Text(
                                  currentPlace,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Inter'),
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          bottom: isShopCardOpen ? 70 : -300,
                          left: 15,
                          right: 15,
                          duration: Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          child: Container(
                            height: 250,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(20)),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        }
      },
    );
  }
}
