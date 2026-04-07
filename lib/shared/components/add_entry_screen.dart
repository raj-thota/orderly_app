import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/leads/controller/leads_controller.dart';

class AddEntryScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialData;

  const AddEntryScreen({super.key, this.initialData});

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  int selectedType = 0;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final noteController = TextEditingController();

  DateTime? selectedDate;
  List<Map<String, dynamic>> items = [];

  final types = ["Lead", "Order", "Follow-up"];

  bool get isEdit => widget.initialData != null;

  @override
  void initState() {
    super.initState();

    if (isEdit) {
      final data = widget.initialData!;

      nameController.text = data["name"] ?? "";
      phoneController.text = data["phone"] ?? "";
      noteController.text = data["msg"] ?? "";

      selectedDate = data["follow_up_date"] != null
          ? DateTime.tryParse(data["follow_up_date"].toString())
          : null;

      final status = data["status"];
      if (status == "closed") {
        selectedType = 1;
        if (data["items"] != null) {
          items = List<Map<String, dynamic>>.from(data["items"]);
        }
      } else if (status == "follow") {
        selectedType = 2;
      }
    }
  }

  double get totalAmount {
    return items.fold(
        0,
        (sum, i) =>
            sum + ((i["qty"] ?? 1) * (i["price"] ?? 0)));
  }

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final controller = ref.read(leadsControllerProvider.notifier);

    final Map<String, dynamic> data = {
      "name": nameController.text.trim(),
      "phone": phoneController.text.trim(),
      "msg": noteController.text.trim(),
      "status": _getStatus(),
      "intent": _getIntent(),
      "follow_up_date": selectedDate?.toIso8601String(),
    };

    if (_getStatus() == "closed") {
      data["order_status"] = "pending";
      data["completed_at"] = now.toIso8601String();
      data["total_amount"] = totalAmount;
      data["items_count"] = items.length;
    }

    try {
      if (isEdit) {
        await controller.editLead(widget.initialData!, data);
      } else {
        await controller.addLead(data, items);
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? "Updated ✅" : "Added ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Something went wrong ❌")),
      );
    }
  }

  String _getStatus() {
    if (selectedType == 1) return "closed";
    if (selectedType == 2) return "follow";
    return "new";
  }

  String _getIntent() {
    if (selectedType == 1) return "order";
    if (selectedType == 2) return "follow_up";
    return "inquiry";
  }

  void addItem() {
    setState(() {
      items.add({"name": "", "qty": 1, "price": 0.0});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Entry" : "Add Entry"),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _typeSelector(),
            const SizedBox(height: 20),

            _card(
              children: [
                _input(nameController, "Customer Name", required: true),
                _input(phoneController, "Phone"),
                _input(noteController, "Notes", maxLines: 3),
              ],
            ),

            const SizedBox(height: 16),

            if (selectedType == 1) _orderSection(),

            if (selectedType == 2) _followUpPicker(),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(isEdit ? "Update" : "Create", style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _input(TextEditingController c, String label,
      {int maxLines = 1, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        validator: required
            ? (v) => v == null || v.isEmpty ? "Required" : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _orderSection() {
    return _card(children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text("Order Items",
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 10),

      ...List.generate(items.length, (index) {
        final item = items[index];

        return Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: item["name"],
                onChanged: (v) => item["name"] = v,
                decoration: const InputDecoration(hintText: "Item"),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 50,
              child: TextFormField(
                initialValue: item["qty"].toString(),
                onChanged: (v) =>
                    item["qty"] = int.tryParse(v) ?? 1,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 70,
              child: TextFormField(
                initialValue: item["price"].toString(),
                onChanged: (v) =>
                    item["price"] = double.tryParse(v) ?? 0,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => items.removeAt(index)),
            ),
          ],
        );
      }),

      TextButton(onPressed: addItem, child: const Text("+ Add Item")),

      Text("Total: ₹${totalAmount.toStringAsFixed(0)}",
          style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _followUpPicker() {
    return _card(children: [
      ListTile(
        title: Text(selectedDate == null
            ? "Select follow-up date"
            : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? DateTime.now(),
            firstDate: DateTime.now(),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setState(() => selectedDate = picked);
          }
        },
      )
    ]);
  }

  Widget _typeSelector() {
    return Row(
      children: List.generate(types.length, (index) {
        final selected = selectedType == index;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedType = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.deepPurple
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  types[index],
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}