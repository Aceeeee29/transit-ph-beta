import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;

class ContributeScreen extends StatefulWidget {
  final void Function(route_model.Route) onRouteSubmitted;

  ContributeScreen({
    super.key,
    void Function(route_model.Route)? onRouteSubmitted,
  }) : onRouteSubmitted = onRouteSubmitted ?? ((_) {});

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _startLocationController =
      TextEditingController();
  final TextEditingController _endLocationController = TextEditingController();
  final TextEditingController _shortDescriptionController =
      TextEditingController();

  List<StepData> steps = [StepData()];

  @override
  void dispose() {
    _startLocationController.dispose();
    _endLocationController.dispose();
    _shortDescriptionController.dispose();
    for (var step in steps) {
      step.instructionController.dispose();
      step.detailsController.dispose();
    }
    super.dispose();
  }

  void _addStep() {
    setState(() {
      steps.add(StepData());
    });
  }

  void _removeStep(int index) {
    setState(() {
      steps[index].instructionController.dispose();
      steps[index].detailsController.dispose();
      steps.removeAt(index);
    });
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Create steps list
      final routeSteps =
          steps.map((stepData) {
            return route_model.Step(
              mode: stepData.mode,
              instruction: stepData.instructionController.text,
              details: stepData.detailsController.text,
            );
          }).toList();

      // Create route
      final route = route_model.Route(
        id: DateTime.now().toString(),
        startLocation: _startLocationController.text,
        endLocation: _endLocationController.text,
        shortDescription: _shortDescriptionController.text,
        steps: routeSteps,
      );

      // Call callback to add route
      widget.onRouteSubmitted(route);

      // Show a snackbar or dialog to confirm submission
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route submitted for review!')),
      );

      // Clear form
      _formKey.currentState!.reset();
      setState(() {
        steps = [StepData()];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribute a Route')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Route Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _startLocationController,
                decoration: const InputDecoration(
                  labelText: 'Starting Location (e.g., SM North EDSA)',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter starting location'
                            : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endLocationController,
                decoration: const InputDecoration(
                  labelText: 'End Location (e.g., Robinsons Galleria)',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter end location'
                            : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortDescriptionController,
                decoration: const InputDecoration(
                  labelText:
                      'Short Description (e.g., SM North to Galleria via MRT)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter short description'
                            : null,
              ),
              const SizedBox(height: 20),
              const Text(
                'Steps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: steps.length,
                itemBuilder: (context, index) {
                  return StepWidget(
                    key: ValueKey(steps[index]),
                    stepData: steps[index],
                    onRemove: () => _removeStep(index),
                  );
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _addStep,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Step'),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      'Submit for Review',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StepData {
  String mode;
  final TextEditingController instructionController;
  final TextEditingController detailsController;

  StepData({
    this.mode = 'Walk',
    TextEditingController? instructionController,
    TextEditingController? detailsController,
  }) : instructionController = instructionController ?? TextEditingController(),
       detailsController = detailsController ?? TextEditingController();
}

class StepWidget extends StatelessWidget {
  final StepData stepData;
  final VoidCallback onRemove;

  const StepWidget({super.key, required this.stepData, required this.onRemove});

  static const List<String> modes = [
    'Walk',
    'Jeepney',
    'Bus',
    'Train',
    'Tricycle',
    'FX/Van',
    'Ferry',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _modeIcon(stepData.mode),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: stepData.mode,
                  items:
                      modes
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode,
                              child: Text(mode),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      stepData.mode = value;
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: stepData.instructionController,
              decoration: const InputDecoration(
                labelText:
                    'Instruction (e.g., Ride a jeep with Cubao terminal)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: stepData.detailsController,
              decoration: const InputDecoration(
                labelText: 'Details (e.g., Drop off at Gateway Mall)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return const Icon(Icons.directions_walk, color: Colors.green);
      case 'Jeepney':
        return const Icon(Icons.directions_bus, color: Colors.blue);
      case 'Bus':
        return const Icon(Icons.directions_bus_filled, color: Colors.red);
      case 'Train':
        return const Icon(Icons.train, color: Colors.purple);
      case 'Tricycle':
        return const Icon(Icons.pedal_bike, color: Colors.orange);
      case 'FX/Van':
        return const Icon(Icons.directions_car, color: Colors.amber);
      case 'Ferry':
        return const Icon(Icons.directions_boat, color: Colors.lightBlue);
      default:
        return const Icon(Icons.directions_walk, color: Colors.green);
    }
  }
}
