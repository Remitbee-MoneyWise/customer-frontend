import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'dart:math' as Math;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:remitbee/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeTestScreen extends StatefulWidget {
  const HomeTestScreen({Key? key}) : super(key: key);

  @override
  State<HomeTestScreen> createState() => HomeTestScreenState();
}

class HomeTestScreenState extends State<HomeTestScreen> {
  GoogleMapController? mapController;
  final LatLng _center =
      const LatLng(45.521563, -122.677433); // Set your desired coordinates
  loc.Location location = loc.Location();
  loc.LocationData? currentLocation;
  Set<Circle> circles = {};
  double selectedRadius = 1.0; // Default radius in kilometers
  Set<Marker> markers = {};
  bool isOpen = false;
  TextEditingController currencyController = TextEditingController();
  String selectedCurrency = "INR";
  String favouriteCurrency = 'INR';
  int? selectedCurrencyRate;
  double? covertedRate;
  bool isShopCardOpen = false;
  bool filterToggled = false;
  String activeFilter = 'All';
  String shopName = '';
  int shopRate = 0;
  double shopScore = 0;
  String currentPlace = '';
  List<String> isoValues = [];
  http.Client client = http.Client();
  late Future _dataFuture;

  List<Map<String, dynamic>> shops = [
    {
      'name': 'Sampath Bank Plc',
      'rate': 15,
      'location': [6.894923, 79.887876],
      'score': 26.78
    },
    {
      'name': 'The Sovereign',
      'rate': 25,
      'location': [6.899408, 79.893693],
      'score': 0.2
    },
    {
      'name': 'Zylan Luxury Villa',
      'rate': 23,
      'location': [6.910101, 79.894931],
      'score': 0.19
    },
    {
      'name': 'Hotel Janaki',
      'rate': 20,
      'location': [6.888039, 79.887449],
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
    _dataFuture = _loadInitialData();
    currencyController.addListener(handleText);
    getFavouriteCurrency().then((value) {
      setState(() {
        selectedCurrency = value;
        favouriteCurrency = value;
        fetchExchangeRate(value);
      });
    });
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([
        fetchExchangeRate(selectedCurrency),
        fetchCurrencies(),
      ]);
    } catch (e) {
      print('Failed to load initial data: $e');
    }
  }

  void handleText() {
    if (currencyController.text.isEmpty) {
      currencyController.text = '1';
    }
  }

  void setFavouriteCurrency(String currency) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('favouriteCurrency', currency);
  }

  void _updatePlaceName() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        currentLocation!.latitude!,
        currentLocation!.longitude!,
      );
      Placemark place = placemarks[0];

      setState(() {
        currentPlace = "${place.locality}, ${place.country}";
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> fetchShopData() async {
    try {
      //code to get the fetch for the data
    } catch (e) {
      print('Could not get shop data: $e');
    }
  }

  Widget buildFilterButton(double width, String filterName) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (activeFilter != filterName) {
            activeFilter = filterName;
            filterToggled = !filterToggled;
          }
        });
      },
      child: Container(
        width: width,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100.0),
          color:
              activeFilter == filterName ? primary : primary.withOpacity(0.85),
        ),
        child: Center(
          child: Text(
            filterName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }

  _getCurrentUserLocation() async {
    bool serviceEnabled;
    loc.PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    location.onLocationChanged.listen((loc.LocationData currentLocation) {
      setState(() {
        this.currentLocation = currentLocation;
        _updateMarkers();
        circles.add(
          Circle(
            circleId: const CircleId('Search Radius'),
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

  Future<String> getFavouriteCurrency() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? currency = prefs.getString('favouriteCurrency');
    return currency ?? 'INR';
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

  Future<List<Marker>> _createMarkers(
    List<Map<String, dynamic>> shops,
    LatLng userLocation,
  ) async {
    List<Map<String, dynamic>> filteredShops =
        _filterShopsByRadius(shops, selectedRadius, userLocation);
    List<Marker> markers = [];
    for (var shop in filteredShops) {
      Uint8List markerIcon = await _textToBitmapData(shop['rate'].toString());
      markers.add(
        Marker(
          markerId: MarkerId(shop['name']),
          position: LatLng(
            shop['location'][0],
            shop['location'][1],
          ),
          onTap: () {
            setState(() {
              isShopCardOpen = !isShopCardOpen;
              shopName = shop['name'];
              shopRate = shop['rate'];
              shopScore = shop['score'];
            });
          },
          icon: BitmapDescriptor.fromBytes(markerIcon),
        ),
      );
    }
    return markers;
  }

  Future<Uint8List> _textToBitmapData(String text) async {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 50,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final width = textPainter.width.toInt() + 20;
    final height = textPainter.height.toInt() + 10;

    final pictureRecorder = PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = primary;
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawRect(rect, paint);
    textPainter.paint(canvas, const Offset(10, 5));

    final img = await pictureRecorder.endRecording().toImage(width, height);
    final pngBytes = await img.toByteData(format: ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }

  void _updateMarkers() async {
    if (currentLocation != null) {
      var newMarkers = await _createMarkers(
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
    try {
      final response = await http.post(
        Uri.parse('https://api.wisecapitals.com/cronjobs/fetchXERate'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic ${base64Encode(
            utf8.encode('ronak:password123test'),
          )}',
        },
        body: jsonEncode(<String, String>{
          'from': from,
          'to': 'LKR',
        }),
      );
      if (response.statusCode == 200) {
        var exchangeRate = jsonDecode(response.body);
        double forwardRate = exchangeRate['forward']['LKR'].toDouble();
        int roundedForwardRate = forwardRate.round();
        selectedCurrencyRate = roundedForwardRate;
      } else {
        throw Exception('Failed to load exchange rate');
      }
      calculateCurrencyRate();
    } catch (e) {
      print('Could not get currency data: $e');
    }
  }

  Future<void> fetchCurrencies() async {
    try {
      String username = 'infozenit28348152';
      String password = 'nfabehsuhv9kif5ji7c744dlou';
      String basicAuth =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final response = await http.get(
        Uri.parse('https://xecdapi.xe.com/v1/currencies.json'),
        headers: <String, String>{
          'authorization': basicAuth,
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonData = jsonDecode(response.body);

        List<dynamic> currencies = jsonData['currencies'];

        isoValues = currencies
            .map<String>((currency) => currency['iso'] as String)
            .toList();
        print(isoValues);
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print('Could not get currency data: $e');
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
          print(selectedCurrency);
          fetchExchangeRate(selectedCurrency);
          isOpen = false;
        });
      },
      child: Container(
        height: 35,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100.0),
          color: selectedCurrency == newSelectedCurrency
              ? primary
              : primary.withOpacity(0.80),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
                onTap: () {
                  setState(() {
                    favouriteCurrency = newSelectedCurrency;
                    setFavouriteCurrency(favouriteCurrency);
                  });
                },
                child: favouriteCurrency == newSelectedCurrency
                    ? const Icon(
                        Icons.star,
                        color: Colors.white,
                      )
                    : const Icon(
                        Icons.star_border_outlined,
                        color: Colors.white,
                      )),
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

  void _launchMaps(LatLng origin, LatLng destination) async {
    final Uri googleMapsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving');
    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri);
    } else {
      throw 'Could not launch $googleMapsUri';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width =
        MediaQuery.of(context).size.width - MediaQuery.of(context).padding.left;
    return FutureBuilder(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ); // Loading indicator
        } else {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            return Scaffold(
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
                        myLocationButtonEnabled: false,
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
                                    circleId: const CircleId('Search Radius'),
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
                                    borderRadius: BorderRadius.circular(100.0),
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
                                                focusedBorder: InputBorder.none,
                                                enabledBorder: InputBorder.none,
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
                                          duration:
                                              const Duration(milliseconds: 400),
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
                        top: 80.0,
                        right: 15.0,
                        child: Container(
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Column(
                            children: [
                              buildFilterButton(width * 0.25, 'All'),
                              const SizedBox(
                                height: 10,
                              ),
                              buildFilterButton(width * 0.25, 'Nearest'),
                              const SizedBox(
                                height: 10,
                              ),
                              buildFilterButton(width * 0.25, 'Best Rates'),
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
                            height: isOpen ? 400 : 0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            width: width * 0.375,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: isoValues.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                      bottom:
                                          8.0), // Change the value as needed
                                  child: buildSelectCurrency(
                                      isoValues[index], isoValues[index]),
                                );
                              },
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
                            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(20)),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      isShopCardOpen = !isShopCardOpen;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.only(top: 20),
                                child: Column(
                                  children: [
                                    Text(
                                      shopName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 15,
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Rate',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                  fontFamily: 'Inter',
                                                ),
                                              ),
                                              Text(
                                                '$shopRate LKR',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                  fontFamily: 'Inter',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Score',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                  fontFamily: 'Inter',
                                                ),
                                              ),
                                              Text(
                                                '$shopScore',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                  fontFamily: 'Inter',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                      height: 20,
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        _launchMaps(
                                          LatLng(
                                            currentLocation!.latitude!,
                                            currentLocation!.longitude!,
                                          ),
                                          LatLng(
                                            shops[0]['location'][0],
                                            shops[0]['location'][1],
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        width: double.infinity,
                                        height: 25,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(100.0),
                                          color: Colors.white,
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Get Directions',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: primary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w400,
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    ],
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
