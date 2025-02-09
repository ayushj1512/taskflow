// ignore_for_file: unused_field

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:taskflow/login.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class Todo {
  String id; // Firestore Document ID
  String title;
  String description;
  String date;
  String priority;
  bool isDone;

  Todo({
    this.id = '',
    required this.title,
    required this.description,
    required this.date,
    required this.priority,
    this.isDone = false,
  });

  // Convert Todo object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date,
      'priority': priority,
      'isDone': isDone,
    };
  }

  // Convert Firestore document to Todo object
  factory Todo.fromMap(DocumentSnapshot doc) {
    return Todo(
      id: doc.id,
      title: doc['title'],
      description: doc['description'],
      date: doc['date'],
      priority: doc['priority'],
      isDone: doc['isDone'],
    );
  }
}

class TodoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TodoScreen(),
    );
  }
}

class TodoScreen extends StatefulWidget {
  @override
  _TodoScreenState createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  List<Todo> _todos = [];
  List<Todo> _filteredTodos = [];
  TextEditingController _searchController = TextEditingController();
  String _selectedPriority = "All";
  String _selectedStatus = "All";
  bool _isAscending = true; // Track sorting order
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionReference _taskCollection =
      FirebaseFirestore.instance.collection('tasks');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterTasks);
    _fetchTasks();
  }

  void _fetchTasks() async {
    try {
      // Get the current user's ID
      String? userId = _auth.currentUser?.uid;
      if (userId == null) {
        print("❌ Error: No user is logged in.");
        return;
      }

      // Reference to the user's task collection
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .get();

      setState(() {
        _todos = snapshot.docs.map((doc) => Todo.fromMap(doc)).toList();
        _filteredTodos = List.from(_todos);
      });

      print("✅ Tasks fetched successfully.");
    } catch (error) {
      print("❌ Error fetching tasks: $error");
    }
  }

  void _addTask(Todo task) async {
    try {
      // Get the current user's ID
      String? userId = _auth.currentUser?.uid;
      if (userId == null) {
        print("❌ Error: No user is logged in.");
        return;
      }

      // Reference to the user's task collection
      CollectionReference taskCollection = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks');

      // Add task to Firestore
      DocumentReference docRef = await taskCollection.add(task.toMap());

      // Assign Firestore-generated ID to the task
      task.id = docRef.id;

      // Update Firestore document to include the generated ID
      await docRef.update({'id': task.id});

      // Update local state
      setState(() {
        _todos.add(task);
        _filteredTodos = List.from(_todos);
      });

      print("✅ Task added successfully with ID: ${task.id}");
    } catch (error) {
      print("❌ Error adding task: $error");
    }
  }

  void _logout() async {
    await _auth.signOut();
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (context) => Login())); // Navigate to Login
  }

  void _toggleSortingOrder() {
    setState(() {
      _isAscending = !_isAscending; // Toggle sorting order
      _applyFilters(); // Apply sorting again
    });
  }

  void _editTask(int index, Todo updatedTask) async {
    if (updatedTask.id.isEmpty) {
      print("❌ Error: Task ID is empty!");
      return;
    }

    try {
      // Get the current user's ID
      String? userId = _auth.currentUser?.uid;
      if (userId == null) {
        print("❌ Error: No user is logged in.");
        return;
      }

      // Reference to the specific task document
      DocumentReference docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .doc(updatedTask.id);

      await docRef.update(updatedTask.toMap());

      setState(() {
        _todos[index] = updatedTask;
        _filteredTodos = List.from(_todos);
      });

      print("✅ Task updated successfully!");
    } catch (e) {
      print("❌ Firestore update error: $e");
    }
  }

  void _deleteTask(int index) async {
    try {
      // Get the current user's ID
      String? userId = _auth.currentUser?.uid;
      if (userId == null) {
        print("❌ Error: No user is logged in.");
        return;
      }

      // Reference to the task document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .doc(_todos[index].id)
          .delete();

      setState(() {
        _todos.removeAt(index);
        _filteredTodos = List.from(_todos);
      });

      print("✅ Task deleted successfully!");
    } catch (error) {
      print("❌ Error deleting task: $error");
    }
  }

  void _toggleTask(int index) async {
    Todo task = _filteredTodos[index];
    bool newStatus = !task.isDone; // Toggle status

    try {
      // 🔹 Ensure Firestore reference is correct
      DocumentReference docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_auth.currentUser?.uid) // Ensure user-specific data
          .collection('tasks')
          .doc(task.id);

      // 🔹 Update Firestore
      await docRef.update({'isDone': newStatus});

      // 🔹 Update local state
      setState(() {
        task.isDone = newStatus;
        _filteredTodos[index] = task;
        int originalIndex = _todos.indexWhere((t) => t.id == task.id);
        if (originalIndex != -1) {
          _todos[originalIndex] = task;
        }
      });

      print("✅ Task '${task.title}' updated: isDone = ${task.isDone}");
    } catch (e) {
      print("❌ Firestore update error: $e");
    }
  }

  void _filterTasks() {
    _applyFilters();
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();

    setState(() {
      _filteredTodos = _todos.where((task) {
        bool matchesSearch = task.title.toLowerCase().contains(query);
        bool matchesPriority =
            (_selectedPriority == "All" || task.priority == _selectedPriority);
        bool matchesStatus = (_selectedStatus == "All") ||
            (_selectedStatus == "Completed" && task.isDone == true) ||
            (_selectedStatus == "Not Completed" && task.isDone == false);

        return matchesSearch && matchesPriority && matchesStatus;
      }).toList();

      // Sorting tasks based on selected order
      _filteredTodos.sort((a, b) {
        int comparison = _parseDate(a.date).compareTo(_parseDate(b.date));
        return _isAscending ? comparison : -comparison; // Toggle order
      });
    });
  }

// Helper function to parse date (assuming date is stored as a String)
  DateTime _parseDate(String dateString) {
    try {
      return DateFormat('dd/MM/yyyy')
          .parse(dateString); // Change format if needed
    } catch (e) {
      return DateTime(2100); // Default far-future date if parsing fails
    }
  }

  void _navigateToAddTask() async {
    final newTask = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen()),
    );

    if (newTask != null) {
      _addTask(newTask);
    }
  }

  void _navigateToEditTask(int index) async {
    final updatedTask = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(
            task:
                _filteredTodos[index]), // 🔹 Fix: Pass the correct task object
      ),
    );

    if (updatedTask != null) {
      _editTask(index, updatedTask);
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = DateFormat('EEEE, MMMM d, y').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromRGBO(106, 165, 254, 1),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To-Do List',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              formattedDate, // Displaying today's date
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              color: Colors.white,
            ),
            onPressed: _toggleSortingOrder,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, size: 28, color: Colors.white),
            onSelected: (value) {
              setState(() {
                if (value == "All") {
                  _selectedPriority = "All";
                  _selectedStatus = "All";
                } else if (["High", "Medium", "Low"].contains(value)) {
                  _selectedPriority = value;
                } else {
                  _selectedStatus = value;
                }
                _applyFilters();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  "Filter by Priority",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black54),
                ),
              ),
              PopupMenuItem(
                value: "High",
                child: ListTile(
                  leading: Icon(Icons.priority_high, color: Colors.red),
                  title: Text("High Priority"),
                ),
              ),
              PopupMenuItem(
                value: "Medium",
                child: ListTile(
                  leading: Icon(Icons.flag, color: Colors.orange),
                  title: Text("Medium Priority"),
                ),
              ),
              PopupMenuItem(
                value: "Low",
                child: ListTile(
                  leading: Icon(Icons.low_priority, color: Colors.green),
                  title: Text("Low Priority"),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  "Filter by Status",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black54),
                ),
              ),
              PopupMenuItem(
                value: "Completed",
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text("Completed"),
                ),
              ),
              PopupMenuItem(
                value: "Not Completed",
                child: ListTile(
                  leading: Icon(Icons.cancel, color: Colors.red),
                  title: Text("Not Completed"),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: "All",
                child: ListTile(
                  leading: Icon(Icons.refresh, color: Colors.blue),
                  title: Text("Reset Filters"),
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: _logout, // Call logout function
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search Tasks',
                  prefixIcon: Icon(Icons.search, color: Colors.blue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredTodos.length,
                  itemBuilder: (context, index) {
                    return Card(
                      elevation: 5,
                      margin: EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: _filteredTodos[index].isDone
                          ? Colors.greenAccent.shade100
                          : Colors.white,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: ListTile(
                          leading: Checkbox(
                            activeColor: Colors.black,
                            value: _filteredTodos[index].isDone,
                            onChanged: (_) => _toggleTask(index),
                          ),
                          title: Text(
                            _filteredTodos[index].title.toUpperCase(),
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              decoration: _filteredTodos[index].isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 16, color: Colors.blue),
                                  SizedBox(width: 4),
                                  Text(
                                    _filteredTodos[index].date,
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.black54),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.flag, size: 16, color: Colors.red),
                                  SizedBox(width: 4),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getPriorityColor(
                                          _filteredTodos[index].priority),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _filteredTodos[index].priority,
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                "📝 ${_filteredTodos[index].description}",
                                style: TextStyle(
                                    fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _navigateToEditTask(index),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTask(index),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color.fromRGBO(255, 121, 0, 1),
        onPressed: _navigateToAddTask,
        child: Icon(Icons.add, size: 30, color: Colors.white),
      ),
    );
  }
}

class AddTaskScreen extends StatefulWidget {
  final Todo? task;

  AddTaskScreen({this.task});

  @override
  _AddTaskScreenState createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  TextEditingController _titleController = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  String _selectedDate = "Select Date";
  String _selectedPriority = "Medium";

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description;
      _selectedDate = widget.task!.date;
      _selectedPriority = widget.task!.priority;
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  void _saveTask() {
    if (_titleController.text.isNotEmpty &&
        _descriptionController.text.isNotEmpty &&
        _selectedDate != "Select Date") {
      Todo newTask = Todo(
        id: widget.task?.id ?? '', // 🔹 Preserve Firestore ID if editing
        title: _titleController.text,
        description: _descriptionController.text,
        date: _selectedDate,
        priority: _selectedPriority,
      );

      Navigator.pop(context, newTask);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? "Add Task" : "Edit Task"),
        backgroundColor: Color.fromRGBO(106, 165, 254, 1),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: "Title",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.title, color: Colors.blue),
                          ),
                        ),
                        SizedBox(height: 10),
                        TextField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: "Description",
                            border: OutlineInputBorder(),
                            prefixIcon:
                                Icon(Icons.description, color: Colors.blue),
                          ),
                          maxLines: 3,
                        ),
                        SizedBox(height: 10),
                        InkWell(
                          onTap: () => _pickDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "Due Date",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_today,
                                  color: Colors.blue),
                            ),
                            child: Text(
                              _selectedDate,
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _selectedPriority,
                          decoration: InputDecoration(
                            labelText: "Priority",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.flag, color: Colors.blue),
                          ),
                          items: ["High", "Medium", "Low"]
                              .map((priority) => DropdownMenuItem(
                                    value: priority,
                                    child: Text(priority),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedPriority = value!;
                            });
                          },
                        ),
                        SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saveTask,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color.fromRGBO(255, 121, 0, 1),
                              padding: EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              widget.task == null ? "Save Task" : "Update Task",
                              style:
                                  TextStyle(fontSize: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _getPriorityColor(String priority) {
  switch (priority) {
    case "High":
      return Colors.red;
    case "Medium":
      return Colors.orange;
    case "Low":
      return Colors.green;
    default:
      return Colors.blue;
  }
}
