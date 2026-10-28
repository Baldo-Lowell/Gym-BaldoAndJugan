import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ────────── SUPABASE CONFIG ──────────
// Supabase Dashboard > Project Settings > API.
// Either paste the values below, or pass them when running:
//   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
//               --dart-define=SUPABASE_ANON_KEY=your-anon-key
// The anon key is safe to ship in the app (Row Level Security protects data).
// NEVER put the Xendit secret key or the Supabase service_role key in this app.
const String kSupabaseUrl = 'https://ucysoikplkcjagaftihg.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVjeXNvaWtwbGtjamFnYWZ0aWhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxNzg5OTcsImV4cCI6MjEwODc1NDk5N30.ELSQBX9oSoyAaT_lceDLCUju6H_8989WyB159Q1fQ-4';
 
SupabaseClient get db => Supabase.instance.client;

// ────────── APP + NAVIGATION ──────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kSupabaseUrl.contains('YOUR-PROJECT') ||
        kSupabaseAnonKey == 'YOUR-ANON-KEY') {
      throw Exception('Supabase URL / anon key not set in main.dart');
    }
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
    CloudStore.ready = true;
  } catch (e) {
    debugPrint('Supabase init failed: $e');
  }
  runApp(const GymApp());
}

class GymApp extends StatelessWidget {
  const GymApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jugan Gym',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const _pages = <Widget>[
    ProteinScreen(),
    BodyScreen(),
    WorkoutScreen(),
    TimerScreen(),
    WaterScreen(),
    ShopScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text(db.auth.currentUser?.email ?? '',
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: index, children: _pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.egg_alt_outlined), label: 'Protein'),
          NavigationDestination(
              icon: Icon(Icons.monitor_weight_outlined), label: 'Body'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center), label: 'Workout'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Rest'),
          NavigationDestination(
              icon: Icon(Icons.water_drop_outlined), label: 'Water'),
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined), label: 'Shop'),
        ],
      ),
    );
  }
}


// ────────── CALCULATORS / LOGIC ──────────

enum Sex { male, female }

enum ActivityLevel {
  sedentary('Sedentary (little exercise)', 1.2),
  light('Light (1-3 days/week)', 1.375),
  moderate('Moderate (3-5 days/week)', 1.55),
  active('Very active (6-7 days/week)', 1.725);

  final String label;
  final double factor;
  const ActivityLevel(this.label, this.factor);
}

enum Goal {
  buildMuscle('Build muscle', 1.8, 300),
  maintain('Maintain', 1.4, 0),
  loseFat('Lose fat', 2.0, -400);

  final String label;
  final double proteinPerKg;
  final int calorieAdjust;
  const Goal(this.label, this.proteinPerKg, this.calorieAdjust);
}

class ProteinResult {
  final double target;
  final double min;
  final double max;
  final double perMeal;
  const ProteinResult(this.target, this.min, this.max, this.perMeal);
}

/// Protein: ~1.6-2.2 g/kg for muscle gain (ISSN position stand).
/// Older adults (65+) benefit from the higher end.
ProteinResult calcProtein({
  required double weightKg,
  required int age,
  required Goal goal,
  int meals = 4,
}) {
  double perKg = goal.proteinPerKg;
  if (age >= 65) perKg += 0.2;
  final low = goal == Goal.buildMuscle ? 1.6 : perKg - 0.4;
  final high = goal == Goal.buildMuscle ? 2.2 : perKg + 0.3;
  final target = weightKg * perKg;
  return ProteinResult(target, weightKg * low, weightKg * high, target / meals);
}

double calcBmi(double weightKg, double heightCm) {
  final m = heightCm / 100;
  return weightKg / (m * m);
}

String bmiCategory(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

/// Mifflin-St Jeor equation.
double calcBmr({
  required double weightKg,
  required double heightCm,
  required int age,
  required Sex sex,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return sex == Sex.male ? base + 5 : base - 161;
}

double calcTdee(double bmr, ActivityLevel a) => bmr * a.factor;

/// Epley one-rep-max estimate.
double calcOneRepMax(double weight, int reps) {
  if (reps <= 1) return weight;
  return weight * (1 + reps / 30);
}

/// Daily water target in ml (~35 ml/kg plus training allowance).
int calcWaterMl(double weightKg) => (weightKg * 35 + 500).round();

double roundTo(double v, int places) {
  final f = pow(10, places);
  return (v * f).round() / f;
}


// ────────── SUPABASE (PER-USER RECORDS) ──────────

/// Saves results to the Supabase table `user_records`
/// (one row per saved result, owned by the logged-in user via Row Level Security).
class CloudStore {
  static bool ready = false;
  static final _rnd = Random();

  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch}${_rnd.nextInt(100000)}';

  /// Returns true if the write reached Supabase.
  static Future<bool> save(
    String collection,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    if (!ready || db.auth.currentUser == null) return false;
    try {
      await db.from('user_records').upsert({
        'id': id ?? newId(),
        'user_id': db.auth.currentUser!.id,
        'collection': collection,
        'data': data,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      debugPrint('Supabase save failed: $e');
      return false;
    }
  }

  static Future<void> delete(String collection, String id) async {
    if (!ready) return;
    try {
      await db
          .from('user_records')
          .delete()
          .eq('id', id)
          .eq('collection', collection)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Supabase delete failed: $e');
    }
  }

  /// Save, then tell the user whether it worked.
  static Future<void> saveWithFeedback(
    BuildContext context,
    String collection,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await save(collection, data, id: id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Saved to Supabase ✓'
          : 'Could not save to Supabase (check internet / table policies)'),
    ));
  }
}


// ────────── PROTEIN SCREEN ──────────

class ProteinScreen extends StatefulWidget {
  const ProteinScreen({super.key});

  @override
  State<ProteinScreen> createState() => _ProteinScreenState();
}

class _ProteinScreenState extends State<ProteinScreen> {
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Goal goal = Goal.buildMuscle;
  int meals = 4;
  ProteinResult? result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _age.text = p.getString('age') ?? '';
      _height.text = p.getString('height') ?? '';
      _weight.text = p.getString('weight') ?? '';
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('age', _age.text.trim());
    await p.setString('height', _height.text.trim());
    await p.setString('weight', _weight.text.trim());
  }

  String? _validate(String? v, double min, double max) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return 'Enter a number';
    if (n < min || n > max) return 'Between $min and $max';
    return null;
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _save();
    final weightKg = double.parse(_weight.text.trim());
    final age = int.parse(_age.text.trim().split('.').first);
    final res = calcProtein(
      weightKg: weightKg,
      age: age,
      goal: goal,
      meals: meals,
    );
    setState(() => result = res);

    CloudStore.saveWithFeedback(context, 'protein_results', {
      'age': age,
      'heightCm': double.tryParse(_height.text.trim()),
      'weightKg': weightKg,
      'goal': goal.label,
      'meals': meals,
      'proteinTargetG': roundTo(res.target, 1),
      'proteinMinG': roundTo(res.min, 1),
      'proteinMaxG': roundTo(res.max, 1),
      'proteinPerMealG': roundTo(res.perMeal, 1),
      'date': DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Protein Calculator',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('How much protein you need each day',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Age (years)', border: OutlineInputBorder()),
                validator: (v) => _validate(v, 14, 100),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Height (cm)', border: OutlineInputBorder()),
                validator: (v) => _validate(v, 100, 250),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)', border: OutlineInputBorder()),
                validator: (v) => _validate(v, 30, 300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Goal>(
          initialValue: goal,
          decoration: const InputDecoration(
              labelText: 'Goal', border: OutlineInputBorder()),
          items: [
            for (final g in Goal.values)
              DropdownMenuItem(value: g, child: Text(g.label)),
          ],
          onChanged: (g) => setState(() => goal = g ?? goal),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Meals per day'),
            Expanded(
              child: Slider(
                value: meals.toDouble(),
                min: 2,
                max: 6,
                divisions: 4,
                label: '$meals',
                onChanged: (v) => setState(() => meals = v.round()),
              ),
            ),
            Text('$meals'),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _calculate,
          icon: const Icon(Icons.calculate),
          label: const Text('Calculate'),
        ),
        if (result != null) ...[
          const SizedBox(height: 24),
          _ResultCard(result: result!, meals: meals),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ProteinResult result;
  final int meals;
  const _ResultCard({required this.result, required this.meals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Daily protein target',
                style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text('${result.target.round()} g',
                style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer)),
            Text(
                'Range: ${result.min.round()} - ${result.max.round()} g per day',
                style: TextStyle(color: cs.onPrimaryContainer)),
            const Divider(height: 28),
            Text('About ${result.perMeal.round()} g per meal ($meals meals)',
                style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 12),
            Text(
              'Based on 1.6-2.2 g of protein per kg of body weight for muscle gain. '
              'This is a general guide, not medical advice. Check with a doctor if you have kidney problems.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}


// ────────── BODY & CALORIES SCREEN ──────────

class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Sex sex = Sex.male;
  ActivityLevel activity = ActivityLevel.moderate;
  Goal goal = Goal.buildMuscle;

  double? bmi;
  double? bmr;
  double? tdee;
  double? target;

  String? _v(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'Enter a number';
    return null;
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final w = double.parse(_weight.text.trim());
    final h = double.parse(_height.text.trim());
    final a = double.parse(_age.text.trim()).round();
    final r = calcBmr(weightKg: w, heightCm: h, age: a, sex: sex);
    final t = calcTdee(r, activity);
    final bmiValue = calcBmi(w, h);
    final targetKcal = t + goal.calorieAdjust;
    setState(() {
      bmi = bmiValue;
      bmr = r;
      tdee = t;
      target = targetKcal;
    });

    CloudStore.saveWithFeedback(context, 'body_results', {
      'sex': sex.name,
      'age': a,
      'heightCm': h,
      'weightKg': w,
      'activity': activity.label,
      'goal': goal.label,
      'bmi': roundTo(bmiValue, 1),
      'bmiCategory': bmiCategory(bmiValue),
      'bmr': r.round(),
      'tdee': t.round(),
      'dailyTargetKcal': targetKcal.round(),
      'date': DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Body & Calories',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('BMI, maintenance calories and daily target',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        SegmentedButton<Sex>(
          segments: const [
            ButtonSegment(value: Sex.male, label: Text('Male')),
            ButtonSegment(value: Sex.female, label: Text('Female')),
          ],
          selected: {sex},
          onSelectionChanged: (s) => setState(() => sex = s.first),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Age (years)', border: OutlineInputBorder()),
                validator: _v,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Height (cm)', border: OutlineInputBorder()),
                validator: _v,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)', border: OutlineInputBorder()),
                validator: _v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ActivityLevel>(
          initialValue: activity,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Activity level', border: OutlineInputBorder()),
          items: [
            for (final a in ActivityLevel.values)
              DropdownMenuItem(value: a, child: Text(a.label)),
          ],
          onChanged: (a) => setState(() => activity = a ?? activity),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Goal>(
          initialValue: goal,
          decoration: const InputDecoration(
              labelText: 'Goal', border: OutlineInputBorder()),
          items: [
            for (final g in Goal.values)
              DropdownMenuItem(value: g, child: Text(g.label)),
          ],
          onChanged: (g) => setState(() => goal = g ?? goal),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _calculate,
          icon: const Icon(Icons.calculate),
          label: const Text('Calculate'),
        ),
        if (bmi != null) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('BMI',
                      '${roundTo(bmi!, 1)} (${bmiCategory(bmi!)})'),
                  _row('BMR', '${bmr!.round()} kcal'),
                  _row('Maintenance (TDEE)', '${tdee!.round()} kcal'),
                  const Divider(),
                  _row('Daily target (${goal.label})', '${target!.round()} kcal',
                      bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'BMI does not separate muscle from fat, so it can read high for muscular people.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
        fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}


// ────────── WORKOUT LOG SCREEN ──────────

class WorkoutEntry {
  final String exercise;
  final double weight;
  final int reps;
  final int sets;
  final DateTime date;
  final String id; // same id is used for the Supabase row

  WorkoutEntry(this.exercise, this.weight, this.reps, this.sets, this.date,
      {String? id})
      : id = id ?? CloudStore.newId();

  Map<String, dynamic> toJson() => {
        'e': exercise,
        'w': weight,
        'r': reps,
        's': sets,
        'd': date.toIso8601String(),
        'id': id,
      };

  factory WorkoutEntry.fromJson(Map<String, dynamic> j) => WorkoutEntry(
        j['e'] as String,
        (j['w'] as num).toDouble(),
        j['r'] as int,
        j['s'] as int,
        DateTime.parse(j['d'] as String),
        id: j['id'] as String?,
      );
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  static const _key = 'workout_log';
  static const _exercises = [
    'Bench Press',
    'Squat',
    'Deadlift',
    'Overhead Press',
    'Barbell Row',
    'Pull-up',
    'Bicep Curl',
    'Leg Press',
  ];

  final _weight = TextEditingController();
  final _reps = TextEditingController();
  final _sets = TextEditingController(text: '3');

  String exercise = _exercises.first;
  List<WorkoutEntry> log = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => WorkoutEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    setState(() => log = list);
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(log.map((e) => e.toJson()).toList()));
  }

  void _add() {
    final w = double.tryParse(_weight.text.trim());
    final r = int.tryParse(_reps.text.trim());
    final s = int.tryParse(_sets.text.trim());
    if (w == null || r == null || s == null || w < 0 || r <= 0 || s <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid weight, reps and sets')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final entry = WorkoutEntry(exercise, w, r, s, DateTime.now());
    setState(() => log.insert(0, entry));
    _persist();

    CloudStore.saveWithFeedback(
      context,
      'workouts',
      {
        'exercise': entry.exercise,
        'weightKg': entry.weight,
        'reps': entry.reps,
        'sets': entry.sets,
        'estimated1RM': roundTo(calcOneRepMax(entry.weight, entry.reps), 1),
        'date': entry.date.toIso8601String(),
      },
      id: entry.id,
    );
  }

  void _delete(int i) {
    final id = log[i].id;
    setState(() => log.removeAt(i));
    _persist();
    CloudStore.delete('workouts', id);
  }

  double? _best(String ex) {
    double? best;
    for (final e in log.where((e) => e.exercise == ex)) {
      final v = calcOneRepMax(e.weight, e.reps);
      if (best == null || v > best) best = v;
    }
    return best;
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _sets.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = _best(exercise);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Workout Log', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Track lifts and your estimated 1-rep max',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: exercise,
          decoration: const InputDecoration(
              labelText: 'Exercise', border: OutlineInputBorder()),
          items: [
            for (final e in _exercises)
              DropdownMenuItem(value: e, child: Text(e)),
          ],
          onChanged: (v) => setState(() => exercise = v ?? exercise),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Kg', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _reps,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Reps', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sets,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Sets', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add to log'),
        ),
        if (best != null) ...[
          const SizedBox(height: 16),
          Card(
            color: cs.primaryContainer,
            child: ListTile(
              leading: Icon(Icons.emoji_events, color: cs.onPrimaryContainer),
              title: Text('Est. 1RM for $exercise',
                  style: TextStyle(color: cs.onPrimaryContainer)),
              trailing: Text('${roundTo(best, 1)} kg',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer)),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No workouts logged yet.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (var i = 0; i < log.length; i++)
          Dismissible(
            key: ValueKey(log[i].id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: cs.error,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete),
            ),
            onDismissed: (_) => _delete(i),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(log[i].exercise),
              subtitle: Text(
                  '${log[i].sets} x ${log[i].reps} @ ${log[i].weight} kg  -  ${_fmtDate(log[i].date)}'),
            ),
          ),
      ],
    );
  }
}


// ────────── REST TIMER SCREEN ──────────

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const _presets = [30, 60, 90, 120, 180];

  Timer? _timer;
  int total = 90;
  int remaining = 90;
  bool running = false;

  void _select(int seconds) {
    _timer?.cancel();
    setState(() {
      total = seconds;
      remaining = seconds;
      running = false;
    });
  }

  void _toggle() {
    if (running) {
      _timer?.cancel();
      setState(() => running = false);
      return;
    }
    if (remaining == 0) remaining = total;
    setState(() => running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remaining <= 1) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          remaining = 0;
          running = false;
        });
      } else {
        setState(() => remaining--);
      }
    });
  }

  void _reset() => _select(total);

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : remaining / total;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Rest Timer', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Time your rest between sets',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                  ),
                ),
                Text(
                  remaining == 0 ? 'Go!' : _fmt(remaining),
                  style: const TextStyle(
                      fontSize: 52, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final p in _presets)
              ChoiceChip(
                label: Text(_fmt(p)),
                selected: total == p,
                onSelected: (_) => _select(p),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              label: Text(running ? 'Pause' : 'Start'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}


// ────────── WATER TRACKER SCREEN ──────────

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  final _weight = TextEditingController();
  int goalMl = 3000;
  int drunkMl = 0;

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      goalMl = p.getInt('water_goal') ?? 3000;
      // Resets automatically each new day.
      drunkMl = p.getString('water_day') == _today
          ? (p.getInt('water_drunk') ?? 0)
          : 0;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('water_goal', goalMl);
    await p.setInt('water_drunk', drunkMl);
    await p.setString('water_day', _today);
  }

  void _add(int ml) {
    setState(() => drunkMl = (drunkMl + ml).clamp(0, 20000));
    _save();
  }

  void _setGoalFromWeight() {
    final w = double.tryParse(_weight.text.trim());
    if (w == null || w < 30 || w > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a weight between 30 and 300 kg')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => goalMl = calcWaterMl(w));
    _save();
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = (drunkMl / goalMl).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Water Tracker', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Stay hydrated for better training and recovery',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        Center(
          child: Text('$drunkMl / $goalMl ml',
              style:
                  const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress, minHeight: 12),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final ml in [250, 500, 750])
              FilledButton.tonal(
                onPressed: () => _add(ml),
                child: Text('+$ml ml'),
              ),
            OutlinedButton(
              onPressed: () {
                setState(() => drunkMl = 0);
                _save();
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text('Set goal from body weight',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
                onPressed: _setGoalFromWeight, child: const Text('Set')),
          ],
        ),
      ],
    );
  }
}


// ────────── SHOP SCREEN (EQUIPMENT / PROTEIN POWDER / ENERGY DRINKS) ──────────

const String kCurrency = '₱';

/// Payment methods shown at checkout.
/// "Online payment" opens a Xendit page (GCash, Maya, cards, bank...).
const String kPayCash = 'Cash on delivery / pickup';
const String kPayXendit = 'Online payment (GCash, Maya, cards, banks)';
const List<String> kPaymentMethods = [kPayCash, kPayXendit];

enum ShopCategory {
  equipment('Gym Equipment', Icons.fitness_center),
  protein('Protein Powder', Icons.egg_alt),
  drinks('Energy Drinks', Icons.bolt);

  final String label;
  final IconData icon;
  const ShopCategory(this.label, this.icon);
}

class Product {
  final String id;
  final String name;
  final String description;
  final ShopCategory category;
  final double price;
  final int stock;
  final String brand;
  final int lowStockAt; // "low stock" warning level
  final bool visible; // hidden products are not shown to customers

  const Product(
    this.id,
    this.name,
    this.description,
    this.category,
    this.price, {
    this.stock = 20,
    this.brand = '',
    this.lowStockAt = 5,
    this.visible = true,
  });

  /// Builds a product from a row of the Supabase `products` table.
  factory Product.fromRow(Map<String, dynamic> m) {
    return Product(
      m['id'] as String,
      (m['name'] ?? '') as String,
      (m['description'] ?? '') as String,
      ShopCategory.values.firstWhere(
        (c) => c.name == m['category'],
        orElse: () => ShopCategory.equipment,
      ),
      ((m['price'] ?? 0) as num).toDouble(),
      stock: ((m['stock'] ?? 0) as num).toInt(),
      brand: (m['brand'] ?? '') as String,
      lowStockAt: ((m['low_stock_at'] ?? 5) as num).toInt(),
      visible: (m['visible'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'description': description,
        'brand': brand,
        'category': category.name,
        'price': price,
        'stock': stock,
        'low_stock_at': lowStockAt,
        'visible': visible,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Products live in Supabase: table `products` (shared by all users).
class ProductStore {
  static const _wait = Duration(seconds: 10);

  static String newId() => CloudStore.newId();

  /// Live list of products (updates by itself when stock or prices change).
  static Stream<List<Product>> stream() =>
      db.from('products').stream(primaryKey: ['id']).map((rows) {
        final list = rows.map(Product.fromRow).toList();
        list.sort((a, b) {
          final c = a.category.index.compareTo(b.category.index);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      });

  static Future<void> save(Product p) =>
      db.from('products').upsert(p.toRow()).timeout(_wait);

  static Future<void> delete(String id) =>
      db.from('products').delete().eq('id', id).timeout(_wait);

  /// Add or remove stock (never goes below 0). Runs on the server.
  static Future<void> adjustStock(String id, int delta) => db
      .rpc('adjust_stock', params: {'p_id': id, 'p_delta': delta})
      .timeout(_wait);

  /// Load the sample products (kProducts) into Supabase.
  static Future<void> seed() => db
      .from('products')
      .upsert([for (final p in kProducts) p.toRow()])
      .timeout(_wait);
}

/// Sample products. The admin can load these into Supabase once
/// (button on the Admin > Products screen when the shop is empty).
const List<Product> kProducts = [
  // Gym equipment
  Product('eq_dumbbell', 'Adjustable Dumbbell Set (20 kg)',
      'Quick-change plates, rubber grip', ShopCategory.equipment, 2500),
  Product('eq_barbell', 'Olympic Barbell (20 kg)',
      '7 ft bar, knurled grip', ShopCategory.equipment, 6500),
  Product('eq_plates', 'Bumper Plates Pair (10 kg)',
      'Rubber coated, sold as a pair', ShopCategory.equipment, 3200),
  Product('eq_kettlebell', 'Kettlebell (12 kg)',
      'Cast iron, flat base', ShopCategory.equipment, 1400),
  Product('eq_bands', 'Resistance Bands Set',
      '5 levels with door anchor', ShopCategory.equipment, 650),
  Product('eq_rope', 'Speed Jump Rope',
      'Adjustable length, ball bearings', ShopCategory.equipment, 350),
  Product('eq_bench', 'Adjustable Bench',
      'Flat / incline / decline', ShopCategory.equipment, 5800),
  Product('eq_gloves', 'Lifting Gloves',
      'Padded palm with wrist support', ShopCategory.equipment, 450),
  // Protein powder
  Product('pr_whey', 'Whey Protein 2 lb',
      'About 25 g protein per scoop', ShopCategory.protein, 1800),
  Product('pr_whey5', 'Whey Protein 5 lb',
      'Best value, about 25 g per scoop', ShopCategory.protein, 3900),
  Product('pr_isolate', 'Whey Isolate 2 lb',
      'Low carb, low fat, fast absorbing', ShopCategory.protein, 2600),
  Product('pr_casein', 'Casein Protein 2 lb',
      'Slow release, good before bed', ShopCategory.protein, 2300),
  Product('pr_mass', 'Mass Gainer 5 lb',
      'High calorie for hard gainers', ShopCategory.protein, 2800),
  Product('pr_plant', 'Plant Protein 2 lb',
      'Pea and rice blend, dairy free', ShopCategory.protein, 2100),
  // Energy drinks
  Product('dr_energy', 'Energy Drink 500 ml',
      'Caffeine and B vitamins', ShopCategory.drinks, 85),
  Product('dr_energy12', 'Energy Drink 12-pack',
      '12 x 500 ml cans', ShopCategory.drinks, 950),
  Product('dr_preworkout', 'Pre-Workout Powder',
      '30 servings, focus and pump', ShopCategory.drinks, 1600),
  Product('dr_bcaa', 'BCAA Drink Mix',
      'Recovery and hydration, 30 servings', ShopCategory.drinks, 1300),
  Product('dr_electrolyte', 'Electrolyte Drink 6-pack',
      'Zero sugar sports hydration', ShopCategory.drinks, 480),
];

class CartLine {
  final Product product;
  final int qty;
  const CartLine(this.product, this.qty);
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const _cartKey = 'shop_cart';
  static const _nameKey = 'shop_name';
  static const _contactKey = 'shop_contact';
  static const _addressKey = 'shop_address';

  ShopCategory category = ShopCategory.equipment;
  final Map<String, int> cart = {}; // productId -> quantity

  String _savedName = '';
  String _savedContact = '';
  String _savedAddress = '';

  List<Product> _products = [];
  bool _loadingProducts = true;
  String? _productsError;
  StreamSubscription<List<Product>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ProductStore.stream().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _products = list;
          _loadingProducts = false;
          _productsError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _loadingProducts = false;
          _productsError = '$e';
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_cartKey);
    final loaded = <String, int>{};
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in m.entries) {
        loaded[e.key] = (e.value as num).toInt();
      }
    }
    setState(() {
      cart
        ..clear()
        ..addAll(loaded);
      _savedName = p.getString(_nameKey) ?? '';
      _savedContact = p.getString(_contactKey) ?? '';
      _savedAddress = p.getString(_addressKey) ?? '';
    });
  }

  Future<void> _persistCart() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cartKey, jsonEncode(cart));
  }

  void _change(Product pr, int delta) {
    if (delta > 0 && pr.stock <= 0) return;
    setState(() {
      // Never more than what is in stock.
      final current = min(cart[pr.id] ?? 0, pr.stock);
      final next = current + delta;
      if (next <= 0) {
        cart.remove(pr.id);
      } else {
        cart[pr.id] = min(next, pr.stock);
      }
    });
    _persistCart();
  }

  List<CartLine> get _lines => [
        for (final p in _products)
          if ((cart[p.id] ?? 0) > 0 && p.stock > 0)
            CartLine(p, min(cart[p.id]!, p.stock)),
      ];

  int get _itemCount => _lines.fold(0, (a, l) => a + l.qty);

  double get _total =>
      _lines.fold(0.0, (a, l) => a + l.product.price * l.qty);

  String _money(double v) =>
      '$kCurrency${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

  Future<void> _checkout() async {
    if (cart.isEmpty) return;
    final nameC = TextEditingController(text: _savedName);
    final contactC = TextEditingController(text: _savedContact);
    final addressC = TextEditingController(text: _savedAddress);
    final formKey = GlobalKey<FormState>();
    String payment = kPaymentMethods.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Place order'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_itemCount item(s) - ${_money(_total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameC,
                  decoration: const InputDecoration(
                      labelText: 'Name', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contactC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone number',
                      border: OutlineInputBorder()),
                  validator: (v) =>
                      (v ?? '').trim().length < 7 ? 'Enter a phone number' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressC,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Delivery address / pickup note',
                      border: OutlineInputBorder()),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter an address' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder()),
                  items: [
                    for (final m in kPaymentMethods)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => payment = v ?? payment,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Confirm order'),
          ),
        ],
      ),
    );

    final name = nameC.text.trim();
    final contact = contactC.text.trim();
    final address = addressC.text.trim();
    // Controllers are not disposed here: the dialog is still animating out
    // and its text fields still use them. They hold no native resources and
    // are garbage collected once the dialog is gone.

    if (confirmed != true || !mounted) return;

    final lines = _lines;
    final orderId = CloudStore.newId();
    final payXendit = payment == kPayXendit;

    // Remember customer details for next time.
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, name);
    await p.setString(_contactKey, contact);
    await p.setString(_addressKey, address);
    _savedName = name;
    _savedContact = contact;
    _savedAddress = address;

    if (!mounted) return;
    final err = await _placeOrder(
      orderId: orderId,
      name: name,
      phone: contact,
      address: address,
      payXendit: payXendit,
      lines: lines,
    );
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (err == null) {
      setState(cart.clear);
      await _persistCart();
      if (payXendit) {
        await _payWithXendit(orderId);
      } else {
        messenger.showSnackBar(
            const SnackBar(content: Text('Order saved to Supabase ✓')));
      }
    } else {
      // Keep the cart so the user can retry.
      messenger.showSnackBar(SnackBar(content: Text('$err Your cart is kept.')));
    }
  }

  /// Asks the server (Supabase Edge Function) for a Xendit payment page, then
  /// shows a dialog that waits until the payment arrives.
  /// The Xendit SECRET key lives only on the server, never in this app.
  Future<void> _payWithXendit(String orderId) async {
    final messenger = ScaffoldMessenger.of(context);
    String? url;
    try {
      final res = await db.functions
          .invoke('create-xendit-invoice', body: {'orderId': orderId})
          .timeout(const Duration(seconds: 30));
      final data = res.data;
      if (data is Map) url = data['invoiceUrl'] as String?;
    } catch (e) {
      debugPrint('Xendit invoice failed: $e');
    }
    if (!mounted) return;
    final link = url;
    if (link == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Order saved, but the payment page could not be opened. Please contact the shop.')));
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(orderId: orderId, url: link),
    );
  }

  /// Calls the server function `place_order`, which checks stock, lowers it and
  /// saves the order in ONE transaction (two people can never buy the last
  /// item, and prices always come from the database).
  /// Returns null on success, or a message.
  Future<String?> _placeOrder({
    required String orderId,
    required String name,
    required String phone,
    required String address,
    required bool payXendit,
    required List<CartLine> lines,
  }) async {
    if (!CloudStore.ready) return 'Supabase is not connected.';
    try {
      await db.rpc('place_order', params: {
        'p_order_id': orderId,
        'p_name': name,
        'p_phone': phone,
        'p_address': address,
        'p_payment': payXendit ? 'xendit' : 'cod',
        'p_items': [
          for (final l in lines) {'productId': l.product.id, 'qty': l.qty},
        ],
      }).timeout(const Duration(seconds: 15));
      return null;
    } on PostgrestException catch (e) {
      // Messages raised by place_order (sold out, only N left...) are shown.
      debugPrint('Order failed: ${e.message}');
      return e.message.isEmpty
          ? 'Could not save order to Supabase.'
          : e.message;
    } catch (e) {
      debugPrint('Order failed: $e');
      return 'Could not save order to Supabase (check internet).';
    }
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          final lines = _lines;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your cart',
                        style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Your cart is empty.',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final l in lines)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l.product.name),
                                subtitle: Text(
                                    '${_money(l.product.price)} x ${l.qty} = ${_money(l.product.price * l.qty)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                      onPressed: () {
                                        _change(l.product, -1);
                                        setSheet(() {});
                                      },
                                    ),
                                    Text('${l.qty}'),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.add_circle_outline),
                                      onPressed: () {
                                        _change(l.product, 1);
                                        setSheet(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_money(_total),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: lines.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _checkout();
                              },
                        icon: const Icon(Icons.shopping_bag),
                        label: const Text('Checkout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final products = _products
        .where((p) => p.visible && p.category == category)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Gym Shop',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            Badge(
              isLabelVisible: _itemCount > 0,
              label: Text('$_itemCount'),
              child: IconButton.filledTonal(
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Equipment, protein powder and energy drinks',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final c in ShopCategory.values)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18),
                label: Text(c.label),
                selected: category == c,
                onSelected: (_) => setState(() => category = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingProducts)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_productsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
                'Could not load products (check internet / table policies).',
                style: TextStyle(color: cs.error)),
          )
        else if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No products here yet.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final p in products)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(p.category.icon, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                            p.brand.isEmpty
                                ? p.description
                                : '${p.brand} - ${p.description}',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(_money(p.price),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cs.primary)),
                        if (p.stock > 0 && p.stock <= p.lowStockAt)
                          Text('Only ${p.stock} left',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.orangeAccent)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p.stock <= 0)
                    Text('Out of stock',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: cs.error))
                  else if ((cart[p.id] ?? 0) == 0)
                    FilledButton.tonal(
                      onPressed: () => _change(p, 1),
                      child: const Text('Add'),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _change(p, -1),
                        ),
                        Text('${cart[p.id]}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _change(p, 1),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (_itemCount > 0) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openCart,
            icon: const Icon(Icons.shopping_cart),
            label: Text('View cart ($_itemCount) - ${_money(_total)}'),
          ),
        ],
      ],
    );
  }
}


// ────────── LOGIN (USER + ADMIN) ──────────

/// Emails that count as ADMIN (the shop manager).
/// Create this account in Supabase Dashboard > Authentication > Users > Add user.
/// Nobody can register as admin from inside the app.
/// Must match the email inside public.is_admin() in supabase/schema.sql.
const List<String> kAdminEmails = ['kingbaldo34@gmail.com'];

bool isAdminEmail(String? email) =>
    email != null && kAdminEmails.contains(email.trim().toLowerCase());

class _MsgException implements Exception {
  final String message;
  const _MsgException(this.message);
}

/// Shows the login screen, or the user app, or the admin panel.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!CloudStore.ready) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Could not connect to Supabase.\n'
              'Check your internet, and that SUPABASE_URL and SUPABASE_ANON_KEY are set in main.dart.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, db.auth.currentSession),
      builder: (context, snap) {
        final user = snap.data?.session?.user ?? db.auth.currentUser;
        if (user == null) return const LoginScreen();
        return isAdminEmail(user.email) ? const AdminShell() : const HomeShell();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool admin = false; // false = User login, true = Admin login
  bool register = false; // create a new user account
  bool busy = false;
  bool hidePass = true;
  String? error;
  String? info;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _authMessage(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    if (code == 'invalid_credentials' || msg.contains('invalid login')) {
      return 'Wrong email or password.';
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return 'Please confirm your email first (check your inbox).';
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return 'An account with this email already exists. Try logging in.';
    }
    if (code == 'weak_password' || msg.contains('password should')) {
      return 'Password is too weak (use at least 6 characters).';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (code == 'email_provider_disabled' || msg.contains('signups not allowed')) {
      return 'Email/Password sign-in is not enabled in Supabase Authentication.';
    }
    if (code == 'validation_failed' || msg.contains('invalid email')) {
      return 'That email address is not valid.';
    }
    return 'Login failed (${e.message}).';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    final email = _email.text.trim().toLowerCase();
    final auth = db.auth;
    try {
      if (admin && !isAdminEmail(email)) {
        throw const _MsgException('This email is not an admin account.');
      }
      if (!admin && isAdminEmail(email)) {
        throw const _MsgException('Admin accounts must use the Admin tab.');
      }
      if (register && !admin) {
        final res = await auth.signUp(email: email, password: _pass.text);
        // When "Confirm email" is ON in Supabase, there is no session yet.
        if (res.session == null) {
          info = 'Account created. Check your email to confirm, then log in.';
          register = false;
        }
      } else {
        await auth.signInWithPassword(email: email, password: _pass.text);
      }
    } on AuthException catch (e) {
      error = _authMessage(e);
    } on _MsgException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong. Please try again.';
      debugPrint('Login error: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = admin
        ? 'Admin login'
        : (register ? 'Create account' : 'User login');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.fitness_center, size: 56, color: cs.primary),
                    const SizedBox(height: 8),
                    Text('Jugan Gym',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            icon: Icon(Icons.person),
                            label: Text('User')),
                        ButtonSegment(
                            value: true,
                            icon: Icon(Icons.admin_panel_settings),
                            label: Text('Admin')),
                      ],
                      selected: {admin},
                      onSelectionChanged: (s) => setState(() {
                        admin = s.first;
                        register = false;
                        error = null;
                        info = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                          labelText: 'Email', border: OutlineInputBorder()),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty || !t.contains('@') || !t.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: hidePass,
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(hidePass
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => hidePass = !hidePass),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 6
                          ? 'At least 6 characters'
                          : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: cs.error)),
                    ],
                    if (info != null) ...[
                      const SizedBox(height: 12),
                      Text(info!, style: TextStyle(color: cs.primary)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(admin
                              ? 'Log in as admin'
                              : (register ? 'Sign up' : 'Log in')),
                    ),
                    if (!admin)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  register = !register;
                                  error = null;
                                  info = null;
                                }),
                        child: Text(register
                            ? 'Already have an account? Log in'
                            : 'No account yet? Sign up'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ────────── ADMIN PANEL (PRODUCTS + STOCK + ORDERS) ──────────

/// Runs an admin action and shows a message when it finishes or fails.
Future<void> _adminRun(
  BuildContext context,
  Future<void> Function() op, {
  String? ok,
}) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await op();
    if (ok != null) {
      m.hideCurrentSnackBar();
      m.showSnackBar(SnackBar(content: Text(ok)));
    }
  } catch (e) {
    debugPrint('Admin action failed: $e');
    m.hideCurrentSnackBar();
    m.showSnackBar(const SnackBar(
        content: Text('Action failed (check internet / table policies).')));
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;

  static const _pages = <Widget>[
    AdminProductsScreen(),
    AdminOrdersScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text('Admin - ${db.auth.currentUser?.email ?? ''}',
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: index, children: _pages)),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ProductFormPage())),
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'Products'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
        ],
      ),
    );
  }
}

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  late final Stream<List<Product>> _stream = ProductStore.stream();
  ShopCategory? filter; // null = all

  Future<void> _confirmDelete(Product p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('"${p.name}" will be removed from the shop.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _adminRun(context, () => ProductStore.delete(p.id),
        ok: 'Product deleted');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Product>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  'Could not load products (check internet / table policies).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error)),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!;
        final shown =
            all.where((p) => filter == null || p.category == filter).toList();
        final low =
            all.where((p) => p.stock > 0 && p.stock <= p.lowStockAt).length;
        final out = all.where((p) => p.stock <= 0).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            Text('Manage Products',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Add items, change prices and control stock',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(label: 'Products', value: '${all.length}'),
                const SizedBox(width: 8),
                _Stat(
                    label: 'Low stock',
                    value: '$low',
                    color: low > 0 ? Colors.orangeAccent : null),
                const SizedBox(width: 8),
                _Stat(
                    label: 'Out of stock',
                    value: '$out',
                    color: out > 0 ? cs.error : null),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: filter == null,
                  onSelected: (_) => setState(() => filter = null),
                ),
                for (final c in ShopCategory.values)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 18),
                    label: Text(c.label),
                    selected: filter == c,
                    onSelected: (_) => setState(() => filter = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (all.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('The shop has no products yet.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _adminRun(
                            context, ProductStore.seed,
                            ok: 'Sample products added'),
                        icon: const Icon(Icons.download),
                        label: const Text('Load sample products'),
                      ),
                      const SizedBox(height: 4),
                      Text('or tap "Add product" to create your own.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No products in this category.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final p in shown) _productCard(p, cs),
          ],
        );
      },
    );
  }

  Widget _productCard(Product p, ColorScheme cs) {
    final out = p.stock <= 0;
    final low = !out && p.stock <= p.lowStockAt;
    final stockColor = out ? cs.error : (low ? Colors.orangeAccent : null);
    final status = out ? 'Out of stock' : (low ? 'Low stock' : 'In stock');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (!p.visible)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Hidden', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
                '${p.category.label}${p.brand.isEmpty ? '' : ' - ${p.brand}'}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (p.description.isNotEmpty)
              Text(p.description,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('$kCurrency${p.price.toStringAsFixed(p.price == p.price.roundToDouble() ? 0 : 2)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'Remove 1 from stock',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: out
                      ? null
                      : () => _adminRun(
                          context, () => ProductStore.adjustStock(p.id, -1)),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${p.stock}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: stockColor)),
                    Text(status,
                        style: TextStyle(fontSize: 10, color: stockColor)),
                  ],
                ),
                IconButton(
                  tooltip: 'Add 1 to stock',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _adminRun(
                      context, () => ProductStore.adjustStock(p.id, 1)),
                ),
                TextButton(
                  onPressed: () => _adminRun(
                      context, () => ProductStore.adjustStock(p.id, 10)),
                  child: const Text('+10'),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ProductFormPage(product: p))),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  onPressed: () => _confirmDelete(p),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add a new product, or edit an existing one.
class ProductFormPage extends StatefulWidget {
  final Product? product;
  const ProductFormPage({super.key, this.product});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  late final _desc =
      TextEditingController(text: widget.product?.description ?? '');
  late final _price = TextEditingController(
      text: widget.product == null ? '' : '${widget.product!.price}');
  late final _stock = TextEditingController(
      text: widget.product == null ? '' : '${widget.product!.stock}');
  late final _low =
      TextEditingController(text: '${widget.product?.lowStockAt ?? 5}');
  late ShopCategory category = widget.product?.category ?? ShopCategory.equipment;
  late bool visible = widget.product?.visible ?? true;
  bool saving = false;

  bool get _editing => widget.product != null;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _desc.dispose();
    _price.dispose();
    _stock.dispose();
    _low.dispose();
    super.dispose();
  }

  String? _num(String? v, {bool whole = false}) {
    final t = (v ?? '').trim();
    final n = whole ? int.tryParse(t) : double.tryParse(t);
    if (n == null) return whole ? 'Enter a whole number' : 'Enter a number';
    if (n < 0) return 'Cannot be negative';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final p = Product(
      widget.product?.id ?? ProductStore.newId(),
      _name.text.trim(),
      _desc.text.trim(),
      category,
      double.parse(_price.text.trim()),
      stock: int.parse(_stock.text.trim()),
      brand: _brand.text.trim(),
      lowStockAt: int.parse(_low.text.trim()),
      visible: visible,
    );
    try {
      await ProductStore.save(p);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(_editing ? 'Product updated' : 'Product added')));
      nav.pop();
    } catch (e) {
      debugPrint('Save product failed: $e');
      if (mounted) setState(() => saving = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save (check internet / table policies).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'Add product')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Product name', border: OutlineInputBorder()),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ShopCategory>(
                initialValue: category,
                decoration: const InputDecoration(
                    labelText: 'Category', border: OutlineInputBorder()),
                items: [
                  for (final c in ShopCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (c) => setState(() => category = c ?? category),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Brand (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Price ($kCurrency)',
                          border: OutlineInputBorder()),
                      validator: _num,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Stock quantity',
                          border: OutlineInputBorder()),
                      validator: (v) => _num(v, whole: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _low,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Low stock warning at (quantity)',
                    border: OutlineInputBorder()),
                validator: (v) => _num(v, whole: true),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show in shop'),
                subtitle: const Text('Turn off to hide it from customers'),
                value: visible,
                onChanged: (v) => setState(() => visible = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_editing ? 'Save changes' : 'Add product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream =
      db.from('orders').stream(primaryKey: ['id']);

  Future<void> _complete(String orderId) async {
    await db
        .from('orders')
        .update({'status': 'completed'})
        .eq('id', orderId)
        .timeout(const Duration(seconds: 10));
  }

  /// Cancels a placed order and puts the items back into stock (server side).
  Future<void> _cancel(String orderId) => db
      .rpc('cancel_order', params: {'p_order_id': orderId})
      .timeout(const Duration(seconds: 15));

  Future<void> _confirmCancel(String orderId) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text('The items will be returned to stock.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep order')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel order')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _adminRun(context, () => _cancel(orderId),
        ok: 'Order cancelled, stock restored');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  'Could not load orders (check internet / table policies).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error)),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!.toList()
          ..sort((a, b) => ((b['date'] ?? '') as String)
              .compareTo((a['date'] ?? '') as String));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Orders', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${rows.length} order(s)',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No orders yet.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final r in rows) _orderCard(r, cs),
          ],
        );
      },
    );
  }

  Widget _orderCard(Map<String, dynamic> m, ColorScheme cs) {
    final id = m['id'] as String;
    final status = (m['status'] ?? 'placed') as String;
    final items = (m['items'] as List?) ?? const [];
    final date = DateTime.tryParse((m['date'] ?? '') as String)?.toLocal();
    final when = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final statusColor = status == 'completed'
        ? Colors.greenAccent
        : (status == 'cancelled' ? cs.error : Colors.orangeAccent);
    final method = m['payment_method'] == 'xendit'
        ? 'Online (Xendit)'
        : 'Cash on delivery / pickup';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((m['customer_name'] ?? '') as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text(status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ],
            ),
            Text('${m['phone'] ?? ''}  -  ${m['address'] ?? ''}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (m['user_email'] != null)
              Text('${m['user_email']}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (when.isNotEmpty)
              Text(when,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const Divider(),
            for (final it in items)
              Text('${(it as Map)['qty']} x ${it['name']}'),
            const SizedBox(height: 6),
            Text(
                'Payment: $method${m['payment_status'] == null ? '' : ' (${m['payment_status']})'}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text(
                'Total: ${m['currency'] ?? kCurrency}${m['total_price'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (status == 'placed' || status == 'awaiting_payment') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _confirmCancel(id),
                    child: const Text('Cancel'),
                  ),
                  if (status == 'placed') ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _adminRun(
                          context, () => _complete(id),
                          ok: 'Order marked completed'),
                      child: const Text('Mark completed'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ────────── XENDIT PAYMENT DIALOG ──────────

/// Opens the Xendit payment page and waits (live) until the order is paid.
/// The order row is updated by the `xendit-webhook` Edge Function when Xendit
/// confirms the payment, and this dialog sees it through Supabase Realtime.
class _PaymentDialog extends StatefulWidget {
  final String orderId;
  final String url;
  const _PaymentDialog({required this.orderId, required this.url});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  String paymentStatus = 'unpaid';
  String status = 'awaiting_payment';

  @override
  void initState() {
    super.initState();
    _open();
    _sub = db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', widget.orderId)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final d = rows.first;
      setState(() {
        paymentStatus = (d['payment_status'] ?? 'unpaid') as String;
        status = (d['status'] ?? '') as String;
      });
    }, onError: (Object e) => debugPrint('Payment watch failed: $e'));
  }

  Future<void> _open() async {
    try {
      await launchUrl(Uri.parse(widget.url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open payment page: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paid = paymentStatus == 'paid';
    final failed = status == 'cancelled' || paymentStatus == 'expired';
    final String title;
    final String text;
    final Widget icon;
    if (paid) {
      title = 'Payment received';
      text = 'Thank you! Your order is confirmed.';
      icon = const Icon(Icons.check_circle, color: Colors.greenAccent, size: 56);
    } else if (failed) {
      title = 'Payment not completed';
      text = 'This payment expired or was cancelled, and the items were put back in stock. You can place the order again.';
      icon = const Icon(Icons.cancel, color: Colors.redAccent, size: 56);
    } else {
      title = 'Complete your payment';
      text = 'Pay on the page that opened (GCash, Maya, card, bank...). '
          'This window updates by itself when your payment arrives. '
          'The payment link expires in 1 hour.';
      icon = const SizedBox(
          height: 40,
          width: 40,
          child: CircularProgressIndicator(strokeWidth: 3));
    }
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        if (!paid && !failed)
          TextButton(
              onPressed: _open, child: const Text('Open payment page')),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(paid || failed ? 'Done' : 'Close'),
        ),
      ],
    );
  }
}
