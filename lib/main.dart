// main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'server_service.dart';


// Add this enum at the top of the file, before the Todo class
enum Priority {
  low,
  medium,
  high
}

// Models
// Update the Todo class by adding priority
class Todo {
  int id;
  String text;
  bool completed;
  DateTime date;
  int repeatDays;
  DateTime? lastCompleted;
  List<String>? tag;
  int order;
  Priority priority; // Add this line

  Todo({
    required this.id,
    required this.text,
    this.completed = false,
    required this.date,
    this.repeatDays = 0,
    this.lastCompleted,
    this.tag,
    required this.order,
    this.priority = Priority.medium, // Add this line with default value
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'date': date.toIso8601String(),
      'repeatDays': repeatDays,
      'lastCompleted': lastCompleted?.toIso8601String(),
      'tags': tag?.toList(), // Convert to List if it's a Set
      'order': order,
      'priority': priority.index,
    };
  }

  static Todo fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as int,
      text: json['text'] as String,
      completed: json['completed'] as bool,
      date: DateTime.parse(json['date'] as String),
      repeatDays: json['repeatDays'] as int,
      lastCompleted: json['lastCompleted'] != null 
          ? DateTime.parse(json['lastCompleted'] as String) 
          : null,
      tag: json['tags'] != null ? List<String>.from(json['tags']) : null,
      order: json['order'] as int,
      priority: Priority.values[json['priority'] ?? Priority.medium.index], // Add this line
    );
  }

  bool isDue() {
    final now = DateTime.now();
    
    if (repeatDays > 0 && lastCompleted != null) {
      final daysSinceCompletion = now.difference(lastCompleted!).inDays;
      return daysSinceCompletion >= repeatDays;
    }
    
    return now.year == date.year && 
           now.month == date.month && 
           now.day == date.day;
  }

    
  bool shouldResetCompletion() {
    if (!completed || repeatDays <= 0 || lastCompleted == null) {
      return false;
    }

    final now = DateTime.now();
    final lastCompletedDate = DateTime(
      lastCompleted!.year, 
      lastCompleted!.month, 
      lastCompleted!.day
    );
    
    // Calculate the next reset date by adding repeatDays to the lastCompleted date
    final nextResetDate = DateTime(
      lastCompletedDate.year,
      lastCompletedDate.month,
      lastCompletedDate.day + repeatDays
    );

    // Convert current date to start of day for comparison
    final currentDate = DateTime(now.year, now.month, now.day);
    
    // Return true if we've reached or passed the reset date
    return currentDate.isAtSameMomentAs(nextResetDate) || 
           currentDate.isAfter(nextResetDate);
  }



  Todo clone() {
    return Todo(
      id: id,
      text: text,
      completed: completed,
      date: date,
      repeatDays: repeatDays,
      lastCompleted: lastCompleted,
      tag: tag != null ? List.from(tag!) : null,
      order: order,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _permissionGranted = false;

  static const String _lastTodayNotificationKey = 'last_today_notification';
  static const String _lastTomorrowNotificationKey = 'last_tomorrow_notification';

  static const String channelIdToday = 'taskify_today';
  static const String channelIdTomorrow = 'taskify_tomorrow';
  static const String channelNameToday = 'Today\'s Tasks';
  static const String channelNameTomorrow = 'Tomorrow\'s Tasks';
  static const String channelDescription = 'Notifications for upcoming tasks';

  Future<void> init() async {
    // Initialize timezone

    // Configure notification channels and settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    // Initialize plugin
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    // Get initial permission status
    await checkPermissionStatus();
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle notification tap here
    // You can add navigation logic or other actions
  }

  Future<bool> checkPermissionStatus() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        final bool? granted = await androidImplementation.areNotificationsEnabled();
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
    } else if (Platform.isIOS) {
      // For iOS, check notification settings
      final bool? result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionGranted = result ?? false;
      return _permissionGranted;
    }
    return false;
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        final bool? granted = await androidImplementation.requestNotificationsPermission();
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
    } else if (Platform.isIOS) {
      final bool? result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionGranted = result ?? false;
      return _permissionGranted;
    }
    return false;
  }

  Future<bool> _shouldSendNotification(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final lastNotificationTime = prefs.getInt(key) ?? 0;
    final now = DateTime.now();
    final lastNotification = DateTime.fromMillisecondsSinceEpoch(lastNotificationTime);
    
    // Check if last notification was on a different day
    if (now.year != lastNotification.year ||
        now.month != lastNotification.month ||
        now.day != lastNotification.day) {
      // Update last notification time
      await prefs.setInt(key, now.millisecondsSinceEpoch);
      return true;
    }
    return false;
  }

  Future<void> checkAndSendDueTaskNotifications(List<Todo> todos, bool notificationsEnabled) async {
  if (!notificationsEnabled || !_permissionGranted) {
    debugPrint('Notifications disabled or permission not granted');
    return;
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(Duration(days: 1));

  // Filter tasks due today and tomorrow
  final dueTodayTasks = todos.where((todo) => 
    !todo.completed && 
    DateTime(todo.date.year, todo.date.month, todo.date.day).isAtSameMomentAs(today)
  ).toList();

  final dueTomorrowTasks = todos.where((todo) => 
    !todo.completed && 
    DateTime(todo.date.year, todo.date.month, todo.date.day).isAtSameMomentAs(tomorrow)
  ).toList();

  // Check and send notification for today's tasks
  if (dueTodayTasks.isNotEmpty) {
    final shouldSendToday = await _shouldSendNotification(_lastTodayNotificationKey);
    if (shouldSendToday) {
      await _showTaskNotification(
        id: 1,
        channelId: channelIdToday,
        channelName: channelNameToday,
        title: 'Tasks Due Today',
        tasks: dueTodayTasks,
        isToday: true,
      );
    }
  }

  // Check and send notification for tomorrow's tasks
  if (dueTomorrowTasks.isNotEmpty) {
    final shouldSendTomorrow = await _shouldSendNotification(_lastTomorrowNotificationKey);
    if (shouldSendTomorrow) {
      await _showTaskNotification(
        id: 2,
        channelId: channelIdTomorrow,
        channelName: channelNameTomorrow,
        title: 'Tasks Due Tomorrow',
        tasks: dueTomorrowTasks,
        isToday: false,
      );
    }
  }
}

  // Add method to reset notification timestamps (useful for testing)
  Future<void> resetNotificationTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastTodayNotificationKey);
    await prefs.remove(_lastTomorrowNotificationKey);
  }

  Future<void> _showTaskNotification({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required List<Todo> tasks,
    required bool isToday,
  }) async {
    // Create detailed task list
    final String tasksList = tasks
        .map((task) => '• ${task.text} (${_getPriorityText(task.priority)})')
        .join('\n');

    // Create notification details
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      enableLights: true,
      color: Color(0xFFD23B45),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      styleInformation: BigTextStyleInformation(
        'You have ${tasks.length} task${tasks.length > 1 ? 's' : ''} due ${isToday ? 'today' : 'tomorrow'}:\n$tasksList',
        htmlFormatContent: true,
        contentTitle: title,
        htmlFormatContentTitle: true,
        summaryText: '${tasks.length} task${tasks.length > 1 ? 's' : ''} due',
        htmlFormatSummaryText: true,
      ),
      actions: [
        const AndroidNotificationAction('view', 'View Tasks'),
        const AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: tasks.length,
        threadIdentifier: channelId,
        categoryIdentifier: 'taskify_tasks',
      ),
    );

    // Show notification
    await _notifications.show(
      id,
      title,
      'You have ${tasks.length} task${tasks.length > 1 ? 's' : ''} due ${isToday ? 'today' : 'tomorrow'}',
      notificationDetails,
      payload: 'tasks_${isToday ? "today" : "tomorrow"}',
    );
  }

  String _getPriorityText(Priority priority) {
    switch (priority) {
      case Priority.high:
        return '⚡ High';
      case Priority.medium:
        return '○ Medium';
      case Priority.low:
        return '▽ Low';
      default:
        return '';
    }
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  bool get isPermissionGranted => _permissionGranted;
}
 
class TodoState extends ChangeNotifier {
  static const String _todosKey = 'todos';
  static const String _darkModeKey = 'darkMode';
  static const String _accentColorKey = 'accentColor';
  static const String _tagsKey = 'tags';  
  static const String _usernameKey = 'username'; // Add this line
  Priority? _filterPriority;
  static const String _notificationsEnabledKey = 'notificationsEnabled';
  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;



  List<Todo> _todos = [];
  bool _darkMode = true;
  Color _accentColor = const Color.fromARGB(255, 210, 59, 69);
  bool _animations = true;
  List<String> _tags = ['Personal', 'Work', 'Shopping']; 
  String _filterType = 'all';
  String _filterTag = 'all'; // Renamed from _filterCategory
  String _username = 'User';
  Priority? get filterPriority => _filterPriority;


  static final Map<String, Color> accentColors = {
    'Blue': Color(0xFF2196F3),
    'Tomato': Color(0xFFD23B45),
    'Purple': Color(0xFF9C27B0),
    'Pink': Color(0xFFE91E63),
    'Orange': Color(0xFFFF5722),
    'Green': Color(0xFF4CAF50),
    'SalmonPink': Color.fromARGB(255, 255, 143, 177),
    'Yellow': Color.fromARGB(255, 255, 196, 0),
  };

  Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(_usernameKey) ?? 'User'; // Add this line
    _darkMode = prefs.getBool(_darkModeKey) ?? true;
    _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;
    
    final colorValue = prefs.getInt(_accentColorKey);
    if (colorValue != null) {
      _accentColor = Color(colorValue);
    }
    
    final todosJson = prefs.getStringList(_todosKey);
    if (todosJson != null) {
      _todos = todosJson
          .map((json) => Todo.fromJson(Map<String, dynamic>.from(
              jsonDecode(json) as Map)))
          .toList();
    }

    // Load tags
    final tags = prefs.getStringList(_tagsKey);
    if (tags != null) {
      _tags = tags;
    }

    _webInterfaceEnabled = prefs.getBool(_webInterfaceEnabledKey) ?? false;
    if (_webInterfaceEnabled) {
      await _serverService.startServer(_todos, _username);
    }
    
    notifyListeners();
  }

  static const String _webInterfaceEnabledKey = 'webInterfaceEnabled';
  final _serverService = ServerService();
  bool _webInterfaceEnabled = false;
  bool get webInterfaceEnabled => _webInterfaceEnabled;
  String? get serverUrl => _serverService.serverUrl;

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, _notificationsEnabled);
    await prefs.setBool(_darkModeKey, _darkMode);
    await prefs.setInt(_accentColorKey, _accentColor.value);
    await prefs.setString(_usernameKey, _username); // Add this line
    
    final todosJson = _todos
        .map((todo) => jsonEncode(todo.toJson()))
        .toList();
    await prefs.setStringList(_todosKey, todosJson);

    // Save tags
    await prefs.setStringList(_tagsKey, _tags);

    await prefs.setBool(_webInterfaceEnabledKey, _webInterfaceEnabled);
  }

   // Add new method
  Future<void> toggleWebInterface(bool value) async {
    _webInterfaceEnabled = value;
    if (_webInterfaceEnabled) {
      print('Enabling web interface');
      print('Number of todos: ${_todos.length}');
      if (_todos.isNotEmpty) {
        print('Sample todo data: ${jsonEncode(_todos.first.toJson())}');
      }
      await _serverService.startServer(_todos, _username);
    } else {
      await _serverService.stopServer();
    }
    await saveState();
    notifyListeners();
  }

  // Update this method to refresh web interface when todos change
  void _updateWebInterface() {
    if (_webInterfaceEnabled && _serverService.isRunning) {
      _serverService.startServer(_todos, _username);
    }
  }

  String exportTasks() {
    final tasksData = {
      'tasks': _todos.map((todo) => todo.toJson()).toList(),
      'tags': _tags,
    };
    return jsonEncode(tasksData);
  }

  Future<void> importTasks(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Import tags
      if (data.containsKey('tags')) {
        _tags = List<String>.from(data['tags'] as List);
      }

      // Import tasks
      if (data.containsKey('tasks')) {
        final List<dynamic> tasksJson = data['tasks'] as List;
        _todos = tasksJson.map((json) => Todo.fromJson(json as Map<String, dynamic>)).toList();
      }

      await saveState();
      notifyListeners();
    } catch (e) {
      throw Exception('Invalid import data format');
    }
  }

Future<void> toggleNotifications() async {
    if (!_notificationsEnabled) {
      // User is trying to enable notifications
      final notificationService = NotificationService();
      final bool granted = await notificationService.requestPermissions();
      
      if (granted) {
        _notificationsEnabled = true;
        await notificationService.init();
        await notificationService.checkAndSendDueTaskNotifications(
          _todos,
          _notificationsEnabled
        );
      } else {
        // Permission denied, keep notifications disabled
        _notificationsEnabled = false;
      }
    } else {
      // User is trying to disable notifications
      _notificationsEnabled = false;
      await NotificationService().cancelAllNotifications();
    }
    
    await saveState();
    notifyListeners();
  }

  // Add method to check current permission status
  Future<bool> checkNotificationPermissions() async {
    return await NotificationService().checkPermissionStatus();
  }


  void checkAndResetTasks() {
    bool hasChanges = false;
    final now = DateTime.now();

    for (var todo in _todos) {
      if (todo.shouldResetCompletion()) {
        todo.completed = false;
        // Keep the lastCompleted date for history
        hasChanges = true;
      }
    }
    
    if (hasChanges) {
      saveState();
      notifyListeners();
    }
  }



  List<Todo> get todos => _todos;
  bool get darkMode => _darkMode;
  Color get accentColor => _accentColor;
  bool get animations => _animations;
  List<String> get tags => _tags;
  String get filterTag => _filterTag;
  String get filterType => _filterType;
  Color get darkModeColor => const Color(0xFF1A1A1A);
  String get username => _username;


  // Update the filteredTodos getter
  List<Todo> get filteredTodos {
    return _todos.where((todo) {
      final matchesFilter = _filterType == 'all' ||
          (_filterType == 'active' && !todo.completed) ||
          (_filterType == 'completed' && todo.completed);

      final matchesTag = _filterTag == 'all' || 
          (todo.tag?.contains(_filterTag) ?? false);

      final matchesPriority = _filterPriority == null || 
          todo.priority == _filterPriority;

      return matchesFilter && matchesTag && matchesPriority;
    }).toList()
      ..sort((a, b) {
        if (a.completed != b.completed) {
          return a.completed ? 1 : -1;
        }
        if (a.priority != b.priority) {
          return b.priority.index.compareTo(a.priority.index);
        }
        return a.order.compareTo(b.order);
      });
  }

  List<Todo> get dueTodayTasks {
    final now = DateTime.now();
    return _todos.where((todo) => !todo.completed && todo.isDue()).toList();
  }

  void updateTodo(Todo updatedTodo) {
  final index = _todos.indexWhere((todo) => todo.id == updatedTodo.id);
  if (index != -1) {
    _todos[index] = updatedTodo;
    saveState();
    notifyListeners();
  }
}

 // Add method to set priority filter
  void setFilterPriority(Priority? priority) {
    if (_filterPriority == priority) {
      _filterPriority = null;
    } else {
      _filterPriority = priority;
    }
    notifyListeners();
  }

void setUsername(String name) {
    _username = name.trim().isEmpty ? 'User' : name;
    saveState();
    notifyListeners();
  }

  void toggleAnimations() {
    _animations = !_animations;
    notifyListeners();
  }

  void toggleDarkMode() {
    _darkMode = !_darkMode;
    saveState();
    notifyListeners();
  }

  void deleteTodo(int id) {
    _todos.removeWhere((todo) => todo.id == id);
    saveState();
    _updateWebInterface();
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    saveState();
    notifyListeners();
  }

  void addTodo(Todo todo) {
    _todos.add(todo);
    saveState();
    _updateWebInterface();
    notifyListeners();
  }

  void toggleTodo(int id) {
    final todoIndex = _todos.indexWhere((todo) => todo.id == id);
    if (todoIndex != -1) {
      _todos[todoIndex].completed = !_todos[todoIndex].completed;
      _todos[todoIndex].lastCompleted =
          _todos[todoIndex].completed ? DateTime.now() : null;
      saveState();
      _updateWebInterface();
      notifyListeners();
    }
  }

  // Update methods
  void addTag(String tag) {
    if (!_tags.contains(tag)) {
      _tags.add(tag);
      saveState();
      notifyListeners();
    }
  }

  void deleteTag(String tag) {
    _tags.remove(tag);
    // Remove the tag from all todos that have it
    for (var todo in _todos) {
      todo.tag?.remove(tag);
    }
    saveState();
    notifyListeners();
  }

  void setFilterType(String filterType) {
    _filterType = filterType;
    notifyListeners();
  }

  void setFilterTag(String tag) {
    _filterTag = tag;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final todoState = TodoState();
  await todoState.loadState();
  
  // Check for tasks that need to be reset
  todoState.checkAndResetTasks();

  await ServerService().initializeBackgroundService();
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => todoState,
      child: const TodoApp(),
    ),
  );
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final todoState = context.watch<TodoState>();
    final brightness = todoState.darkMode ? Brightness.dark : Brightness.light;

    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        primaryColor: todoState.accentColor,
        scaffoldBackgroundColor: todoState.darkMode ? todoState.darkModeColor : Colors.white,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: todoState.accentColor.withOpacity(0.4),
              width: 2,
            ),
          ),
        ),
        appBarTheme: AppBarTheme(
          color: todoState.accentColor,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: todoState.accentColor,
        ),
      ),
      home: const TodoScreen(),
    );
  }
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  _TodoScreenState createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int _repeatDays = 0;
  List<String>? _selectedTags;
  bool _showSettings = false;
  late AnimationController _fabAnimationController;
  bool _isFabOpen = false;
  Timer? _taskCheckTimer;
  DateTime? _lastCheckDate;
  late AnimationController _settingsIconController;
  final NotificationService _notificationService = NotificationService();

Future<bool> _onWillPop() async {
    if (_showSettings) {
      setState(() {
        _showSettings = false;
        _settingsIconController.stop();
        _settingsAnimationController.reverse();
      });
      return false; // Don't close the app, just close settings
    }
    return true; // Close the app
  }

  void _checkForDateChange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Only check if the date has changed since last check
    if (_lastCheckDate == null || !today.isAtSameMomentAs(_lastCheckDate!)) {
      _lastCheckDate = today;
      final todoState = context.read<TodoState>();
      todoState.checkAndResetTasks();
    }
  }

  void _exportTasks(TodoState todoState) {
  final data = todoState.exportTasks();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Export Tasks'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copy the text below to save your tasks:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: todoState.accentColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: todoState.accentColor.withOpacity(0.1),
              ),
            ),
            child: SelectableText(
              data,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

void _importTasks(TodoState todoState) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Import Tasks'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste your exported tasks data below:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste your tasks data here...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            try {
              todoState.importTasks(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Tasks imported successfully!'),
                  backgroundColor: todoState.accentColor,
                ),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error importing tasks. Please check your data.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Text('Import'),
        ),
      ],
    ),
  );
}

late AnimationController _settingsAnimationController;
late Animation<Offset> _settingsSlideAnimation;

@override
void initState() {
  super.initState();
  _notificationService.init();
  _fabAnimationController = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 300),
  );

    // Initial check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final todoState = context.read<TodoState>();
      _notificationService.checkAndSendDueTaskNotifications(
        todoState.todos,
        todoState.notificationsEnabled,
      );
    });
    
// Check every minute for date change
    _taskCheckTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      final todoState = context.read<TodoState>();
      _notificationService.checkAndSendDueTaskNotifications(
        todoState.todos,
        todoState.notificationsEnabled,
      );
      _checkForDateChange();
    });

    // Initial check
    _checkForDateChange();

      // Initialize animation controllers with staggered durations
  _settingsAnimationController = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 800),
  );

  // In initState, update the settings animation:
_settingsSlideAnimation = Tween<Offset>(
  begin: Offset(0, -0.2), // Reduced offset for smoother animation
  end: Offset.zero,
).animate(CurvedAnimation(
  parent: _settingsAnimationController,
  curve: Curves.easeOutCubic,
));

// Initialize the settings icon animation controller
    _settingsIconController = AnimationController(
      duration: const Duration(seconds: 3), // One complete rotation takes 3 seconds
      vsync: this,
    );

}


@override
void dispose() {
  _settingsAnimationController.dispose();
  _taskCheckTimer?.cancel();
  _settingsIconController.dispose();
  super.dispose();
}

void _toggleSettings() {
    setState(() {
      _showSettings = !_showSettings;
      if (_showSettings) {
        // Start continuous rotation when settings are shown
        _settingsIconController.repeat();
        _settingsAnimationController.forward();
      } else {
        // Stop rotation when settings are hidden
        _settingsIconController.stop();
        _settingsAnimationController.reverse();
      }
    });
  }

  String _getGreeting() {
  var hour = DateTime.now().hour;
  if (hour < 12) {
    return 'Good Morning,';
  } else if (hour < 17) {
    return 'Good Afternoon,';
  } else {
    return 'Good Evening,';
  }
}

  void _toggleFab() {
    setState(() {
      _isFabOpen = !_isFabOpen;
      if (_isFabOpen) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

void _showEditTaskDialog(Todo todo) {
  _textController.text = todo.text;
  List<String>? selectedTags = todo.tag;
  _selectedDate = todo.date;
  _repeatDays = todo.repeatDays;
  Priority selectedPriority = todo.priority; // Add this line

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Edit Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Task Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              _buildTagSelector(
                context,
                Provider.of<TodoState>(context, listen: false),
                selectedTags,
                (tags) {
                  setDialogState(() => selectedTags = tags);
                },
              ),
              SizedBox(height: 16),
              _buildPrioritySelector( // Add this
                context,
                Provider.of<TodoState>(context, listen: false),
                selectedPriority,
                (priority) {
                  setDialogState(() => selectedPriority = priority);
                },
              ),
                              SizedBox(height: 16),
                ListTile(
                  title: Text('Due Date'),
                  subtitle: Text(DateFormat('MMM d, y').format(_selectedDate)),
                  trailing: Icon(Icons.calendar_today),
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Text('Repeat every: '),
                    DropdownButton<int>(
                      value: _repeatDays,
                      items: [0, 1, 2, 3, 7, 14, 30].map((days) {
                        return DropdownMenuItem(
                          value: days,
                          child: Text(days == 0 ? 'Never' : '$days days'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _repeatDays = value ?? 0;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
          TextButton(
            onPressed: () {
              _resetForm();
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_textController.text.isNotEmpty) {
                final updatedTodo = Todo(
                  id: todo.id,
                  text: _textController.text,
                  date: _selectedDate,
                  tag: selectedTags,
                  repeatDays: _repeatDays,
                  completed: todo.completed,
                  lastCompleted: todo.lastCompleted,
                  order: todo.order,
                  priority: selectedPriority, // Add this line
                );
                context.read<TodoState>().updateTodo(updatedTodo);
                _resetForm();
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    ),
  );
}

  void _showDueTasksNotification() {
    final dueTasks = context.read<TodoState>().dueTodayTasks;
    if (dueTasks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You have ${dueTasks.length} tasks due today!'),
          backgroundColor: context.read<TodoState>().accentColor,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New Tag'),
        content: TextField(
          controller: _categoryController,
          decoration: InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _categoryController.clear();
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_categoryController.text.isNotEmpty) {
                context.read<TodoState>().addTag(_categoryController.text);
                Navigator.pop(context);
                _categoryController.clear();
              }
            },
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog() {
    DateTime selectedDate = _selectedDate;
  int selectedRepeatDays = _repeatDays;
  List<String>? selectedTags = _selectedTags;
  Priority selectedPriority = Priority.medium; // Add this line

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Add New Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Task Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              _buildTagSelector(
                context,
                Provider.of<TodoState>(context, listen: false),
                selectedTags,
                (tags) {
                  setDialogState(() => selectedTags = tags);
                },
              ),
              SizedBox(height: 16),
              _buildPrioritySelector( // Add this
                context,
                Provider.of<TodoState>(context, listen: false),
                selectedPriority,
                (priority) {
                  setDialogState(() => selectedPriority = priority);
                },
              ),
              SizedBox(height: 16),
                ListTile(
                  title: Text('Due Date'),
                  subtitle: Text(DateFormat('MMM d, y').format(selectedDate)),
                  trailing: Icon(Icons.calendar_today),
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Text('Repeat every: '),
                    DropdownButton<int>(
                      value: selectedRepeatDays,
                      items: [0, 1, 2, 3, 7, 14, 30].map((days) {
                        return DropdownMenuItem(
                          value: days,
                          child: Text(days == 0 ? 'Never' : '$days days'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedRepeatDays = value ?? 0;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
          TextButton(
            onPressed: () {
              _resetForm();
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_textController.text.isNotEmpty) {
                context.read<TodoState>().addTodo(
                  Todo(
                    id: DateTime.now().millisecondsSinceEpoch,
                    text: _textController.text,
                    date: selectedDate,
                    tag: selectedTags,
                    repeatDays: selectedRepeatDays,
                    order: context.read<TodoState>().todos.length,
                    priority: selectedPriority, // Add this line
                  ),
                );
                _resetForm();
                Navigator.pop(context);
              }
            },
            child: Text('Add'),
          ),
        ],
      ),
    ),
  );
}

void _showRepeatDialog(Todo todo) {
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Repeat Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Repeat every:'),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1, 2, 3, 7, 14, 30].map((days) =>
                ElevatedButton(
                  onPressed: () {
                    setDialogState(() {
                      todo.repeatDays = days;
                    });
                    // Update the TodoState
                    Provider.of<TodoState>(context, listen: false).notifyListeners();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: todo.repeatDays == days ? 
                      Provider.of<TodoState>(context, listen: false).accentColor : null,
                    foregroundColor: todo.repeatDays == days ? 
                      Colors.white : null,
                  ),
                  child: Text('$days d'),
                ),
              ).toList(),
            ),
            TextButton(
              child: Text('Clear'),
              onPressed: () {
                setDialogState(() {
                  todo.repeatDays = 0;
                });
                // Update the TodoState
                Provider.of<TodoState>(context, listen: false).notifyListeners();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _resetForm() {
  _textController.clear();
  setState(() {
    _selectedTags = null; // Changed from _selectedCategory = null
    _repeatDays = 0;
    _selectedDate = DateTime.now();
  });
}

  Widget _buildEditableUsername(TodoState todoState) {
  return InkWell(
    onTap: () {
      // Show dialog to edit username
      final TextEditingController controller = TextEditingController(text: todoState.username);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Username'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
            maxLength: 14,
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                todoState.setUsername(controller.text);
                Navigator.pop(context);
              },
              child: Text('Save'),
            ),
          ],
        ),
      );
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          todoState.username,
          style: TextStyle(
            fontSize: 20,
            color: todoState.accentColor.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: 4),
        Icon(
          Icons.edit,
          size: 16,
          color: todoState.accentColor.withOpacity(0.6),
        ),
      ],
    ),
  );
}

Widget _buildPrioritySelector(
  BuildContext context,
  TodoState todoState,
  Priority currentPriority,
  Function(Priority) onPriorityChanged,
) {
  return Container(
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Priority',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: Priority.values.map((priority) {
            final isSelected = priority == currentPriority;
            return InkWell(
              onTap: () => onPriorityChanged(priority),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _getPriorityColor(priority)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getPriorityColor(priority),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPriorityIcon(priority),
                      size: 16,
                      color: isSelected ? Colors.white : _getPriorityColor(priority),
                    ),
                    SizedBox(width: 4),
                    Text(
                      _getPriorityText(priority),
                      style: TextStyle(
                        color: isSelected ? Colors.white : _getPriorityColor(priority),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}

// Add these helper methods to get priority-related UI elements
Color _getPriorityColor(Priority priority) {
  switch (priority) {
    case Priority.low:
      return Colors.green;
    case Priority.medium:
      return Colors.orange;
    case Priority.high:
      return Colors.red;
  }
}

IconData _getPriorityIcon(Priority priority) {
  switch (priority) {
    case Priority.low:
      return Icons.arrow_downward;
    case Priority.medium:
      return Icons.remove;
    case Priority.high:
      return Icons.arrow_upward;
  }
}

String _getPriorityText(Priority priority) {
  switch (priority) {
    case Priority.low:
      return 'Low';
    case Priority.medium:
      return 'Medium';
    case Priority.high:
      return 'High';
  }
}

Widget _buildSettingsCard(TodoState todoState) {
  return Card(
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: todoState.accentColor.withOpacity(0.4),
        width: 1,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8, // Constrain height to 80% of screen
        ),
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  todoState.accentColor.withOpacity(0.1),
                  Colors.transparent,
                ],
                stops: [0.0, 5],
              ),
            ),
            child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: todoState.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RotationTransition(
                      turns: _settingsIconController,
                      child: Icon(
                        Icons.settings,
                        color: todoState.accentColor,
                        size: 20,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: todoState.accentColor,
                    ),
                  ),
                ],
              ),
                  const SizedBox(height: 16),
                  // Dark Mode Switch
                  Container(
                    decoration: BoxDecoration(
                      color: todoState.accentColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: todoState.accentColor.withOpacity(0.1),
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        'Dark Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      value: todoState.darkMode,
                      onChanged: (_) => todoState.toggleDarkMode(),
                      activeColor: todoState.accentColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Update the settings card notification toggle:
Container(
  decoration: BoxDecoration(
    color: todoState.accentColor.withOpacity(0.05),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: todoState.accentColor.withOpacity(0.1),
    ),
  ),
  child: FutureBuilder<bool>(
    future: todoState.checkNotificationPermissions(),
    builder: (context, snapshot) {
      final bool hasPermission = snapshot.data ?? false;
      
      return SwitchListTile(
        title: Text(
          'Push Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          hasPermission 
              ? 'Get notified about tasks due today and tomorrow'
              : 'Permission required for notifications',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        value: todoState.notificationsEnabled && hasPermission,
        onChanged: (_) => todoState.toggleNotifications(),
        activeColor: todoState.accentColor,
      );
    },
  ),
),
const SizedBox(height: 16),
Container(
  decoration: BoxDecoration(
    color: todoState.accentColor.withOpacity(0.05),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: todoState.accentColor.withOpacity(0.1),
    ),
  ),
  child: SwitchListTile(
    title: Text(
      'Web Interface',
      style: TextStyle(
        fontWeight: FontWeight.w500,
      ),
    ),
    subtitle: Text(
      todoState.webInterfaceEnabled && todoState.serverUrl != null
          ? 'Available at: ${todoState.serverUrl}'
          : 'Access your tasks from web browser',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).textTheme.bodySmall?.color,
      ),
    ),
    value: todoState.webInterfaceEnabled,
    onChanged: (value) => todoState.toggleWebInterface(value),
    activeColor: todoState.accentColor,
  ),
),                  const SizedBox(height: 16),
                  // Tags Section
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: todoState.accentColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: todoState.accentColor.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tags',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextButton.icon(
                              icon: Icon(
                                Icons.add,
                                color: todoState.accentColor,
                              ),
                              label: Text(
                                'Add',
                                style: TextStyle(
                                  color: todoState.accentColor,
                                ),
                              ),
                              onPressed: _showAddCategoryDialog,
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: todoState.tags.map((category) {
                            return Chip(
                              label: Text(
                                category,
                                style: TextStyle(
                                  color: todoState.accentColor,
                                ),
                              ),
                              backgroundColor: todoState.accentColor.withOpacity(0.1),
                              deleteIcon: Icon(
                                Icons.close,
                                size: 18,
                                color: todoState.accentColor,
                              ),
                              onDeleted: () => todoState.deleteTag(category),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Accent Color Section
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: todoState.accentColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: todoState.accentColor.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Accent Color',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: TodoState.accentColors.entries.map((entry) {
                            return InkWell(
                              onTap: () => todoState.setAccentColor(entry.value),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: entry.value,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: todoState.accentColor == entry.value
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: entry.value.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Backup & Restore Section
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: todoState.accentColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: todoState.accentColor.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Backup & Restore',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.upload_file),
                                label: Text('Export'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: todoState.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => _exportTasks(todoState),
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.download),
                                label: Text('Import'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: todoState.accentColor.withOpacity(0.1),
                                  foregroundColor: todoState.accentColor,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => _importTasks(todoState),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // App Info Section
                  Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: todoState.accentColor.withOpacity(0.05),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: todoState.accentColor.withOpacity(0.1),
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'App Info',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.code,
          color: todoState.accentColor,
        ),
        title: Text('Developer'),
        subtitle: Text('Andrew Mikhail (Cyber752)'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.app_shortcut,
          color: todoState.accentColor,
        ),
        title: Text('Taskify v1.0.0'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your task simplified.'),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(Icons.favorite),
          label: Text('Support'),
          style: ElevatedButton.styleFrom(
            backgroundColor: todoState.accentColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () async {
            final Uri url = Uri.parse('https://ko-fi.com/cyber752');
            try {
              if (!await launchUrl(
                url,
                mode: LaunchMode.externalApplication,
              )) {
                throw Exception('Could not launch $url');
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not open the support page. Please try again.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
    ],
  ),
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

Widget _buildFilterChips(TodoState todoState) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Tags section (at top)
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: todoState.tags.map((tag) => Padding(
            padding: EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(tag),
              selected: todoState.filterTag == tag,
              onSelected: (_) => todoState.setFilterTag(
                todoState.filterTag == tag ? 'all' : tag
              ),
              backgroundColor: todoState.accentColor.withOpacity(0.1),
              selectedColor: todoState.accentColor,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          )).toList(),
        ),
      ),
      SizedBox(height: 12),

      // Priority filters
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: Priority.values.map((priority) {
            return Padding(
              padding: EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPriorityIcon(priority),
                      size: 16,
                      color: todoState.filterPriority == priority 
                          ? Colors.white 
                          : _getPriorityColor(priority),
                    ),
                    SizedBox(width: 4),
                    Text(_getPriorityText(priority)),
                  ],
                ),
                selected: todoState.filterPriority == priority,
                onSelected: (_) => todoState.setFilterPriority(priority),
                backgroundColor: _getPriorityColor(priority).withOpacity(0.1),
                selectedColor: _getPriorityColor(priority),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ),
      SizedBox(height: 12),

      // Divider between priority and task states
      Divider(
        color: todoState.accentColor.withOpacity(0.2),
        thickness: 1,
      ),
      SizedBox(height: 12),

      // Status filters with Clear Completed option
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // Clear Completed button (only shown if there are completed tasks)
            // Inside _buildFilterChips method, update the Clear Completed ActionChip:

// Clear Completed button (only shown if there are completed non-repeating tasks)
if (todoState.todos.any((todo) => todo.completed && todo.repeatDays == 0))
  Padding(
    padding: EdgeInsets.only(right: 8),
    child: ActionChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline,
            size: 16,
            color: Colors.red,
          ),
          SizedBox(width: 4),
          Text(
            'Clear Completed',
            style: TextStyle(color: Colors.red),
          ),
        ],
      ),
      backgroundColor: Colors.red.withOpacity(0.1),
      onPressed: () {
        // Count how many tasks will be deleted
        final tasksToDelete = todoState.todos
            .where((todo) => todo.completed && todo.repeatDays == 0)
            .length;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Clear Completed Tasks'),
            content: Text(
              'Are you sure you want to delete $tasksToDelete completed non-repeating ${tasksToDelete == 1 ? 'task' : 'tasks'}?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  // Remove only completed tasks that don't have repeat days
                  todoState.todos.removeWhere(
                    (todo) => todo.completed && todo.repeatDays == 0
                  );
                  todoState.saveState();
                  todoState.notifyListeners();
                  Navigator.pop(context);
                  
                  // Show confirmation snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted $tasksToDelete completed ${tasksToDelete == 1 ? 'task' : 'tasks'}'),
                      backgroundColor: todoState.accentColor,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
            
            // Regular status filters
            FilterChip(
              label: Text('All'),
              selected: todoState.filterType == 'all',
              onSelected: (_) => todoState.setFilterType('all'),
              backgroundColor: todoState.accentColor.withOpacity(0.1),
              selectedColor: todoState.accentColor,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            SizedBox(width: 8),
            FilterChip(
              label: Text('Active'),
              selected: todoState.filterType == 'active',
              onSelected: (_) => todoState.setFilterType('active'),
              backgroundColor: todoState.accentColor.withOpacity(0.1),
              selectedColor: todoState.accentColor,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            SizedBox(width: 8),
            FilterChip(
              label: Text('Completed'),
              selected: todoState.filterType == 'completed',
              onSelected: (_) => todoState.setFilterType('completed'),
              backgroundColor: todoState.accentColor.withOpacity(0.1),
              selectedColor: todoState.accentColor,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ],
        ),
      ),
    ],
  );
}
// Add a method to show filter stats
Widget _buildFilterStats(TodoState todoState) {
  final totalTasks = todoState.filteredTodos.length;
  final completedTasks = todoState.filteredTodos.where((todo) => todo.completed).length;
  
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Text(
          'Showing ${totalTasks} task${totalTasks != 1 ? 's' : ''}',
          style: TextStyle(
            color: todoState.accentColor.withOpacity(0.8),
          ),
        ),
        if (todoState.filterPriority != null) ...[
          Text(
            ' • ${_getPriorityText(todoState.filterPriority!)} priority',
            style: TextStyle(
              color: _getPriorityColor(todoState.filterPriority!),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        Spacer(),
        Text(
          '$completedTasks completed',
          style: TextStyle(
            color: Colors.grey,
          ),
        ),
      ],
    ),
  );
}

 
Widget _buildTodoItem(Todo todo, TodoState todoState) {
  final isOverdue = !todo.completed && todo.date.isBefore(DateTime.now());
  final isDueToday = !todo.completed && todo.isDue();

  return AnimatedContainer(
    duration: todoState.animations ? const Duration(milliseconds: 300) : Duration.zero,
    curve: Curves.easeInOut,
    transform: Matrix4.identity()..scale(todo.completed && todoState.animations ? 0.98 : 1.0),
    margin: EdgeInsets.symmetric(vertical: 6),
    child: Card(
      elevation: todo.completed ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: todo.completed 
              ? todoState.accentColor.withOpacity(0.2)
              : _getPriorityColor(todo.priority).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                _getPriorityColor(todo.priority).withOpacity(0.1),
                Colors.transparent,
              ],
              stops: [0.0, 0.3],
            ),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Stack(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => todoState.toggleTodo(todo.id),
                        customBorder: CircleBorder(),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: todo.completed
                                  ? _getPriorityColor(todo.priority)
                                  : _getPriorityColor(todo.priority).withOpacity(0.5),
                              width: 2,
                            ),
                            color: todo.completed
                                ? _getPriorityColor(todo.priority).withOpacity(0.1)
                                : Colors.transparent,
                          ),
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            todo.completed ? Icons.check : null,
                            size: 16,
                            color: _getPriorityColor(todo.priority),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getPriorityColor(todo.priority),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).cardColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(
                  todo.text,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: todo.completed ? FontWeight.normal : FontWeight.w600,
                    decoration: todo.completed ? TextDecoration.lineThrough : null,
                    color: todo.completed
                        ? Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.6)
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                subtitle: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
        // Date indicator first
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isOverdue
                ? Colors.red.withOpacity(0.1)
                : isDueToday
                    ? _getPriorityColor(todo.priority).withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOverdue
                    ? Icons.warning
                    : isDueToday
                        ? Icons.today
                        : Icons.calendar_today,
                size: 14,
                color: isOverdue
                    ? Colors.red
                    : isDueToday
                        ? _getPriorityColor(todo.priority)
                        : Colors.grey,
              ),
              SizedBox(width: 4),
              Text(
                DateFormat('MMM d').format(todo.date),
                style: TextStyle(
                  fontSize: 12,
                  color: isOverdue
                      ? Colors.red
                      : isDueToday
                          ? _getPriorityColor(todo.priority)
                          : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Priority indicator AFTER date
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getPriorityColor(todo.priority).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getPriorityIcon(todo.priority),
                size: 14,
                color: _getPriorityColor(todo.priority),
              ),
              SizedBox(width: 4),
              Text(
                _getPriorityText(todo.priority),
                style: TextStyle(
                  fontSize: 12,
                  color: _getPriorityColor(todo.priority),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Tags LAST
        if (todo.tag != null && todo.tag!.isNotEmpty) ...[
          SizedBox(width: 8),
          ...todo.tag!.map((tag) => Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: todoState.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 12,
                color: todoState.accentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          )).toList(),
        ],
      ],
    ),
  ),
),
                trailing: Container(
  width: todo.repeatDays > 0 ? 140 : 96,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (todo.repeatDays > 0)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: todoState.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                size: 16,
                color: todoState.accentColor,
              ),
              SizedBox(width: 4),
              Text(
                '${todo.repeatDays}d',
                style: TextStyle(
                  fontSize: 12,
                  color: todoState.accentColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      IconButton(
        icon: Icon(Icons.edit_outlined),
        onPressed: () => _showEditTaskDialog(todo),
        color: todoState.accentColor,
        tooltip: 'Edit task',
        splashRadius: 24,
        constraints: BoxConstraints(minWidth: 40),
        padding: EdgeInsets.all(8),
      ),
      IconButton(
        icon: Icon(Icons.delete_outline),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete Task'),
              content: Text('Are you sure you want to delete this task?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    todoState.deleteTodo(todo.id);
                  },
                  child: Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        },
        color: Colors.red.withOpacity(0.8),
        tooltip: 'Delete task',
        splashRadius: 24,
        constraints: BoxConstraints(minWidth: 40),
        padding: EdgeInsets.all(8),
      ),
    ],
  ),
),
              ),
              if (todo.lastCompleted != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: todoState.accentColor.withOpacity(0.05),
                    border: Border(
                      top: BorderSide(
                        color: todoState.accentColor.withOpacity(0.1),
                      ),
                    ),
                  ),
                  child: Text(
                    'Last completed: ${DateFormat('MMM d, y h:mm a').format(todo.lastCompleted!)}', // Updated format
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
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

Widget _buildTagSelector(
  BuildContext context,
  TodoState todoState,
  List<String>? currentTags,
  Function(List<String>?) onTagsChanged,
) {
  return InkWell(
    onTap: () {
      showDialog(
        context: context,
        builder: (context) {
          List<String> tempSelectedTags = List.from(currentTags ?? []);
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('Select Tags'),
                content: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: todoState.tags.map((tag) {
                      final isSelected = tempSelectedTags.contains(tag);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(tag),
                        selectedColor: todoState.accentColor.withOpacity(0.2),
                        checkmarkColor: todoState.accentColor,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              tempSelectedTags.add(tag);
                            } else {
                              tempSelectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onTagsChanged(tempSelectedTags.isEmpty ? null : tempSelectedTags);
                    },
                    child: Text('Done'),
                  ),
                ],
              );
            },
          );
        },
      );
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Tags (Optional)',
        border: OutlineInputBorder(),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: currentTags?.isEmpty ?? true
            ? [Text('No tags selected', style: TextStyle(color: Colors.grey))]
            : currentTags!.map((tag) => Chip(
                label: Text(tag),
                onDeleted: () {
                  List<String> updatedTags = List.from(currentTags);
                  updatedTags.remove(tag);
                  onTagsChanged(updatedTags.isEmpty ? null : updatedTags);
                },
              )).toList(),
      ),
    ),
  );
}
 

  Widget _buildBottomBar(List<Todo> dueTasks) {
  if (dueTasks.isEmpty) return SizedBox.shrink();

  return Consumer<TodoState>(
    builder: (context, todoState, child) => Container(
      decoration: BoxDecoration(
        color: todoState.accentColor.withOpacity(0.1),
        border: Border(
          top: BorderSide(
            color: todoState.accentColor.withOpacity(0.2),
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            color: todoState.accentColor,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            '${dueTasks.length} task${dueTasks.length > 1 ? 's' : ''} due today',
            style: TextStyle(
              color: todoState.accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Spacer(),
          TextButton(
            onPressed: () {
              todoState.setFilterTag('all');
              todoState.setFilterType('all');
              todoState.setFilterPriority(null);
            },
            child: Text(
              'View All',
              style: TextStyle(
                color: todoState.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
@override
Widget build(BuildContext context) {
  final todoState = context.watch<TodoState>();
  final dueTasks = todoState.dueTodayTasks;

  return WillPopScope( // Wrap Scaffold with WillPopScope
      onWillPop: _onWillPop,
      child: Scaffold(
    body: Stack(
      children: [
        Column(
          children: [
            // Fixed Header Section
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    todoState.accentColor.withOpacity(0.15),
                    todoState.accentColor.withOpacity(0.05),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                color: todoState.darkMode ? todoState.darkModeColor : Colors.white,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // App Title and Settings Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
  children: [
    ColorFiltered(
      colorFilter: ColorFilter.mode(
        todoState.accentColor,
        BlendMode.srcIn,  // This blend mode will color the white parts
      ),
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/taskify_logo.png'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
    SizedBox(width: 8),
    Hero(
      tag: 'app_title',
      child: Text(
        'TASKIFY',
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          color: todoState.accentColor,
        ),
      ),
    ),
                            ],
                          ),
                          IconButton(
                            icon: AnimatedRotation(
                              duration: Duration(milliseconds: 300),
                              turns: _showSettings ? 0.5 : 0,
                              child: Icon(Icons.settings),
                            ),
                            onPressed: _toggleSettings,
                          ),
                        ],
                      ),

                      // Settings or Main Content
                      AnimatedCrossFade(
                        duration: Duration(milliseconds: 300),
                        crossFadeState: _showSettings
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  '${_getGreeting()} ',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: todoState.accentColor.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                _buildEditableUsername(todoState),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 14,
                                color: todoState.accentColor.withOpacity(0.6),
                              ),
                            ),
                            Divider(
                              color: todoState.accentColor.withOpacity(0.2),
                              thickness: 1,
                            ),
                          ],
                        ),
                        
                        secondChild: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: SlideTransition(
                            position: _settingsSlideAnimation,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: _buildSettingsCard(todoState),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                color: todoState.darkMode ? todoState.darkModeColor : Colors.white,
                child: SingleChildScrollView(
                  child: AnimatedOpacity(
                    duration: Duration(milliseconds: 300),
                    opacity: _showSettings ? 0.0 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                      child: Column(
                        children: [
                          if (!_showSettings) ...[
                            _buildFilterChips(todoState),
                          ],
                          SizedBox(height: 16),
                          todoState.filteredTodos.isEmpty
                              ? Container(
                                  height: 300,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_task,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'Use The + Button\nTo Start Adding Your Daily Tasks.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  children: todoState.filteredTodos
                                      .map((todo) => _buildTodoItem(todo, todoState))
                                      .toList(),
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Bar
            AnimatedSlide(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              offset: dueTasks.isNotEmpty ? Offset.zero : Offset(0, 1),
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 300),
                opacity: dueTasks.isNotEmpty ? 1.0 : 0.0,
                child: _buildBottomBar(dueTasks),
              ),
            ),
          ],
        ),

        // Floating Action Button
        Positioned(
          right: 16,
          bottom: dueTasks.isNotEmpty ? 96 : 16,
          child: AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: _showSettings ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: _showSettings,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _fabAnimationController,
                      curve: Curves.easeOut,
                    ),
                    child: FloatingActionButton(
                      heroTag: 'fab_quick',
                      mini: true,
                      child: Icon(Icons.quickreply),
                      onPressed: _toggleFab,
                    ),
                  ),
                  SizedBox(height: 8),
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _fabAnimationController,
                      curve: Curves.easeOut,
                      reverseCurve: Curves.easeIn,
                    ),
                    child: FloatingActionButton(
                      heroTag: 'fab_voice',
                      mini: true,
                      child: Icon(Icons.mic),
                      onPressed: _toggleFab,
                    ),
                  ),
                  SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'fab_main',
                    child: AnimatedRotation(
                      duration: Duration(milliseconds: 300),
                      turns: _isFabOpen ? 0.125 : 0,
                      child: Icon(Icons.add),
                    ),
                    onPressed: () {
                      if (_isFabOpen) {
                        _toggleFab();
                      } else {
                        _showAddTaskDialog();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  ),
  );
}}