// ----------------------------
// FIT PRO - main.dart (PART 1 of 5)
// Contains: imports, main(), app root, theme handling, SplashScreen (internet check + routing)
// ----------------------------

import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Google Mobile Ads SDK
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  runApp(const FitProApp());
}

class FitProApp extends StatefulWidget {
  const FitProApp({super.key});

  @override
  State<FitProApp> createState() => _FitProAppState();
}

class _FitProAppState extends State<FitProApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void setTheme(ThemeMode m) => setState(() => _themeMode = m);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIT PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      themeMode: _themeMode,
      home: SplashScreen(onThemeChange: setTheme),
    );
  }
}

//////////////////////////////////////////////////////////////////////////////
/// SPLASH SCREEN
/// - shows logo
/// - quick branding delay
/// - checks internet connectivity
/// - routes to OnboardingFlow (if not onboarded) or MainTabs (if onboarded)
/// - offline: shows retry button
//////////////////////////////////////////////////////////////////////////////

class SplashScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChange;
  const SplashScreen({super.key, required this.onThemeChange});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _checking = true;
  bool _noInternet = false;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connSub;

  @override
  void initState() {
    super.initState();
    _startSequence();
    _connSub = _connectivity.onConnectivityChanged.listen((event) {
      if (event != ConnectivityResult.none && _noInternet) {
        _startSequence();
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _startSequence() async {
    setState(() {
      _checking = true;
      _noInternet = false;
    });

    await Future.delayed(const Duration(milliseconds: 700));

    final ok = await _checkInternetFast();
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _checking = false;
        _noInternet = true;
      });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('fitpro_onboarded') ?? false;

    if (onboarded) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MainTabs(onThemeChange: widget.onThemeChange)));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OnboardingFlow(onThemeChange: widget.onThemeChange)));
    }
  }

  Future<bool> _checkInternetFast() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 6));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/logo.png', width: 140, height: 140),
            const SizedBox(height: 18),
            const Text('FIT PRO', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Your Body • Your Formula', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            const CircularProgressIndicator(color: Colors.white),
          ]),
        ),
      );
    }

    if (_noInternet) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off, size: 88, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No Internet Connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.0),
              child: Text('FIT PRO requires an active internet connection. Please connect and retry.', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startSequence,
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// ------------------------------
/// Placeholders used in Part1:
/// - OnboardingFlow
/// - MainTabs
/// They will be defined in subsequent parts (PART 2 .. PART 5).
/// ------------------------------
// ----------------------------
// FIT PRO - main.dart (PART 2 of 5)
// Contains: OnboardingFlow (3 pages), permissions request, scrollable, why-online note
// ----------------------------

class OnboardingFlow extends StatefulWidget {
  final Function(ThemeMode) onThemeChange;
  const OnboardingFlow({super.key, required this.onThemeChange});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pc = PageController();
  final TextEditingController _nameCtrl = TextEditingController();
  int _page = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // Example: Storage and Notification permissions (can add more if needed)
    await [
      Permission.storage,
      Permission.notification,
    ].request();
  }

  Future<void> _completeOnboarding() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Please enter your name');
      return;
    }

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fitpro_username', name);
      await prefs.setBool('fitpro_onboarded', true);

      // Request necessary permissions
      await _requestPermissions();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MainTabs(onThemeChange: widget.onThemeChange)));
    } catch (e) {
      _showSnack('Failed to save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _introCard(String title, String subtitle, {IconData? icon}) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) Icon(icon, size: 84, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ]),
      ),
    );
  }

  Widget _nameCard() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text("What's your name?", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Enter your name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          const Text('We will greet you by this name in the app.', style: TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _introCard('Fast. Clean. Minimal.', 'All essential fitness calculators in one modern app.', icon: Icons.speed),
      _introCard('100% Online (Required)', 'FIT PRO requires internet for ads & updates. Offline use is blocked.', icon: Icons.wifi),
      _nameCard(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: pages.length,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => pages[i],
            ),
          ),

          // dots
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(pages.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
              height: 8,
              width: _page == i ? 22 : 8,
              decoration: BoxDecoration(
                color: _page == i ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            );
          })),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
            child: Row(children: [
              if (_page > 0)
                TextButton(
                  onPressed: () {
                    _pc.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  },
                  child: const Text('Back'),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_page < pages.length - 1) {
                          _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                        } else {
                          _completeOnboarding();
                        }
                      },
                style: ElevatedButton.styleFrom(minimumSize: const Size(110, 48)),
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_page == pages.length - 1 ? 'Continue' : 'Next'),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}
// ----------------------------
// FIT PRO - main.dart (PART 3 of 5)
// Contains: MainTabs (4 bottom nav), Home, Tools, FAQs, Settings skeleton
// ----------------------------

class MainTabs extends StatefulWidget {
  final Function(ThemeMode) onThemeChange;
  const MainTabs({super.key, required this.onThemeChange});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;
  String _username = "";
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _loadName();
    _checkInternet();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _username = prefs.getString('fitpro_username') ?? "User");
  }

  Future<void> _checkInternet() async {
    try {
      final lookup = await InternetAddress.lookup("google.com");
      setState(() => _online = lookup.isNotEmpty);
    } catch (e) {
      setState(() => _online = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(online: _online),
      ToolsScreen(online: _online),
      FaqScreen(online: _online),
      SettingsScreen(onThemeChange: widget.onThemeChange),
    ];

    if (!_online) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off, size: 88, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No Internet Connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.0),
              child: Text('FIT PRO requires an active internet connection. Please connect and retry.', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkInternet,
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Hi, $_username 👋"),
      ),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Home"),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: "Tools"),
          NavigationDestination(icon: Icon(Icons.help_outline), label: "FAQs"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Setting"),
        ],
      ),
    );
  }
}

// ----------------------------
// HOME SCREEN
// ----------------------------
class HomeScreen extends StatelessWidget {
  final bool online;
  const HomeScreen({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    final mostUsedTools = ["BMI", "TDEE", "Body Fat"]; // top 3 default
    final allTools = ["BMI", "TDEE", "Body Fat", "Steps→Calories", "Macro Calc", "Water Intake", "BMR", "Heart Rate"];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Most Used Tools", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: mostUsedTools.map((t) => _toolCard(context, t)).toList(),
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsScreen(online: online))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("Explore All Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _toolCard(BuildContext context, String name) {
    return InkWell(
      onTap: () {}, // later: open individual tool screen
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceVariant,
        ),
        child: Center(child: Text(name, textAlign: TextAlign.center)),
      ),
    );
  }
}

// ----------------------------
// TOOLS SCREEN
// ----------------------------
class ToolsScreen extends StatelessWidget {
  final bool online;
  const ToolsScreen({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    final tools = ["BMI", "TDEE", "Body Fat", "Steps→Calories", "Macro Calc", "Water Intake", "BMR", "Heart Rate"];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: tools.map((t) {
        return ListTile(
          title: Text(t),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: online ? () {} : () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Internet required for tools")));
          },
        );
      }).toList()),
    );
  }
}

// ----------------------------
// FAQ SCREEN
// ----------------------------
class FaqScreen extends StatelessWidget {
  final bool online;
  const FaqScreen({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("FAQs", style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        online
            ? const Text("Why online? FIT PRO needs internet for ads, updates & data.")
            : const Text("Internet required to view FAQs"),
      ]),
    );
  }
}

// ----------------------------
// SETTINGS SCREEN
// ----------------------------
class SettingsScreen extends StatelessWidget {
  final Function(ThemeMode) onThemeChange;
  const SettingsScreen({super.key, required this.onThemeChange});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Image.asset('assets/logo.png', width: 120, height: 120),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text("Change Your Name"),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.email),
          title: const Text("Send Feedback (Gmail)"),
          onTap: () {}, // later: open Gmail intent
        ),
        ListTile(
          leading: const Icon(Icons.camera_alt),
          title: const Text("Instagram"),
          onTap: () {}, // later: open Instagram link
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode),
          title: const Text("Theme"),
          trailing: DropdownButton<ThemeMode>(
            value: Theme.of(context).brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
            items: const [
              DropdownMenuItem(value: ThemeMode.light, child: Text("Light")),
              DropdownMenuItem(value: ThemeMode.dark, child: Text("Dark")),
              DropdownMenuItem(value: ThemeMode.system, child: Text("System")),
            ],
            onChanged: (v) {
              if (v != null) onThemeChange(v);
            },
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text("App Info"),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text("Version: 1.0.0"),
            Text("Developer: Piyush"),
          ]),
        ),
      ]),
    );
  }
}
// ----------------------------
// FIT PRO - main.dart (PART 4 of 5)
// Contains: Individual Tool Screens
// ----------------------------

class BmiCalculatorScreen extends StatefulWidget {
  const BmiCalculatorScreen({super.key});
  @override
  State<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends State<BmiCalculatorScreen> {
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  double? _bmi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BMI Calculator")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _weightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Weight (kg)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Height (cm)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(_weightCtrl.text);
              final h = double.tryParse(_heightCtrl.text);
              if (w == null || h == null) return;
              setState(() => _bmi = w / ((h / 100) * (h / 100)));
            },
            child: const Text("Calculate BMI"),
          ),
          const SizedBox(height: 20),
          if (_bmi != null)
            Text("Your BMI: ${_bmi!.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}

class TdeeCalculatorScreen extends StatefulWidget {
  const TdeeCalculatorScreen({super.key});
  @override
  State<TdeeCalculatorScreen> createState() => _TdeeCalculatorScreenState();
}

class _TdeeCalculatorScreenState extends State<TdeeCalculatorScreen> {
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  String _gender = "Male";
  double? _tdee;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("TDEE Calculator")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _weightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Weight (kg)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Height (cm)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ageCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Age (yrs)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text("Gender: "),
            DropdownButton<String>(
              value: _gender,
              items: const [
                DropdownMenuItem(value: "Male", child: Text("Male")),
                DropdownMenuItem(value: "Female", child: Text("Female")),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            )
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(_weightCtrl.text);
              final h = double.tryParse(_heightCtrl.text);
              final a = double.tryParse(_ageCtrl.text);
              if (w == null || h == null || a == null) return;
              double bmr;
              if (_gender == "Male") {
                bmr = 10 * w + 6.25 * h - 5 * a + 5;
              } else {
                bmr = 10 * w + 6.25 * h - 5 * a - 161;
              }
              setState(() => _tdee = bmr * 1.55); // moderate activity
            },
            child: const Text("Calculate TDEE"),
          ),
          const SizedBox(height: 20),
          if (_tdee != null)
            Text("Your TDEE: ${_tdee!.toStringAsFixed(0)} kcal/day", style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}

class FatCalculatorScreen extends StatefulWidget {
  const FatCalculatorScreen({super.key});
  @override
  State<FatCalculatorScreen> createState() => _FatCalculatorScreenState();
}

class _FatCalculatorScreenState extends State<FatCalculatorScreen> {
  final TextEditingController _waistCtrl = TextEditingController();
  final TextEditingController _neckCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _hipCtrl = TextEditingController();
  String _gender = "Male";
  double? _bodyFat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Body Fat %")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (_gender == "Female")
            TextField(
              controller: _hipCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Hip (cm)"),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          TextField(
            controller: _waistCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Waist (cm)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          TextField(
            controller: _neckCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Neck (cm)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Height (cm)"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text("Gender: "),
            DropdownButton<String>(
              value: _gender,
              items: const [
                DropdownMenuItem(value: "Male", child: Text("Male")),
                DropdownMenuItem(value: "Female", child: Text("Female")),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            )
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(_waistCtrl.text);
              final n = double.tryParse(_neckCtrl.text);
              final h = double.tryParse(_heightCtrl.text);
              final hip = double.tryParse(_hipCtrl.text);
              if (w == null || n == null || h == null) return;
              double bf;
              if (_gender == "Male") {
                bf = 495 / (1.0324 - 0.19077 * (log(w - n) / ln10) + 0.15456 * (log(h) / ln10)) - 450;
              } else {
                if (hip == null) return;
                bf = 495 / (1.29579 - 0.35004 * (log(w + hip - n) / ln10) + 0.22100 * (log(h) / ln10)) - 450;
              }
              setState(() => _bodyFat = bf);
            },
            child: const Text("Calculate Body Fat %"),
          ),
          const SizedBox(height: 20),
          if (_bodyFat != null)
            Text("Body Fat: ${_bodyFat!.toStringAsFixed(2)} %", style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}

class StepsCalorieScreen extends StatefulWidget {
  const StepsCalorieScreen({super.key});
  @override
  State<StepsCalorieScreen> createState() => _StepsCalorieScreenState();
}

class _StepsCalorieScreenState extends State<StepsCalorieScreen> {
  final TextEditingController _stepsCtrl = TextEditingController();
  double? _calories;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Steps to Calories")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _stepsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Steps walked"),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final steps = double.tryParse(_stepsCtrl.text);
              if (steps == null) return;
              setState(() => _calories = steps * 0.04); // avg kcal per step
            },
            child: const Text("Calculate Calories"),
          ),
          const SizedBox(height: 20),
          if (_calories != null)
            Text("Calories burned: ${_calories!.toStringAsFixed(1)} kcal", style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}
// ----------------------------
// FIT PRO - main.dart (PART 5 of 5)
// Contains: SettingsScreen, Interstitial Ad, Permissions, Gmail & Instagram links, Theme toggle
// ----------------------------

class SettingsScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChange;
  const SettingsScreen({super.key, required this.onThemeChange});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _name = "";
  String _version = "";
  int _usageCount = 0;
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadVersion();
    _loadUsageCount();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _name = prefs.getString('fitpro_username') ?? "User");
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);
  }

  Future<void> _loadUsageCount() async {
    final prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt('fitpro_usage_count') ?? 0;
    count++;
    await prefs.setInt('fitpro_usage_count', count);
    setState(() => _usageCount = count);

    if (count % 3 == 0) {
      _showInterstitial();
    }
  }

  void _showInterstitial() {
    _interstitialAd = InterstitialAd(
      adUnitId: "ca-app-pub-2139593035914184/9381774418", // ← CHANGE THIS
      request: const AdRequest(),
      listener: AdListener(
        onAdLoaded: (_) => _interstitialAd?.show(),
        onAdFailedToLoad: (ad, err) => ad.dispose(),
        onAdClosed: (ad) => ad.dispose(),
      ),
    )..load();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.notification,
    ].request();
  }

  Future<void> _openEmail() async {
    final Uri mail = Uri(
      scheme: 'mailto',
      path: 'feedback@example.com',
      query: 'subject=FIT PRO Feedback',
    );
    if (!await launchUrl(mail)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open email")));
    }
  }

  Future<void> _openInstagram() async {
    final url = Uri.parse("https://www.instagram.com/your_account_here/");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open Instagram")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Image.asset('assets/logo.png', width: 120, height: 120)),
        const SizedBox(height: 16),
        Text("Name: $_name", style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('fitpro_username');
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => OnboardingFlow(onThemeChange: widget.onThemeChange)),
              (_) => false,
            );
          },
          child: const Text("Change Your Name"),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text("Theme: ", style: TextStyle(fontSize: 18)),
            DropdownButton<ThemeMode>(
              value: Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              items: const [
                DropdownMenuItem(value: ThemeMode.light, child: Text("Light")),
                DropdownMenuItem(value: ThemeMode.dark, child: Text("Dark")),
                DropdownMenuItem(value: ThemeMode.system, child: Text("System")),
              ],
              onChanged: (mode) {
                if (mode != null) widget.onThemeChange(mode);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.email),
          title: const Text("Send Feedback"),
          onTap: _openEmail,
        ),
        ListTile(
          leading: Image.asset('assets/instagram.png', width: 28, height: 28),
          title: const Text("Follow on Instagram"),
          onTap: _openInstagram,
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text("App Version"),
          subtitle: Text(_version),
        ),
        ListTile(
          leading: const Icon(Icons.developer_mode),
          title: const Text("Developer Info"),
          subtitle: const Text("Your Name / Contact Info"),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _requestPermissions,
          child: const Text("Grant Necessary Permissions"),
        ),
      ]),
    );
  }
}