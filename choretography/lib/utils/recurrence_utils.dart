// choretography/lib/utils/recurrence_utils.dart
import '../models/task_model.dart'; // Using relative path

class RecurrenceUtils {
  /// Checks if a task is due on a specific date, considering its recurrence rule and due date.
  static bool isTaskDueOnDate(Task task, DateTime date) {
    // Normalize the date to ignore time components for daily checks
    DateTime checkDate = DateTime(date.year, date.month, date.day);

    if (task.isCompleted) {
      // If the task is already marked as completed, it might not be considered "due"
      // unless the completion is for a previous instance of a recurring task.
      // For simplicity now, if completed, it's not due. This might need refinement.
      // A more advanced system would track completion dates for each instance.
      // return false;
    }

    // Check against one-time due date first
    if (task.dueDate != null) {
      DateTime taskDueDate = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
      if (taskDueDate.isAtSameMomentAs(checkDate)) {
        return true; // Due on its specific due date
      }
      // If it has a specific due date and no recurrence, it's only due on that day.
      if (task.recurrenceRule == null || task.recurrenceRule!.isEmpty) {
        return false;
      }
    }

    // If no recurrence rule, and dueDate didn't match, it's not due on this date.
    if (task.recurrenceRule == null || task.recurrenceRule!.isEmpty) {
      return false;
    }

    final rule = task.recurrenceRule!;
    final type = rule['type'] as String?;

    // The task's original dueDate can serve as the start date for recurrence calculations.
    // If no specific dueDate, recurrence might start from task creation (not tracked here)
    // or a fixed point. For now, let's assume recurrence applies generally from when the task exists.
    // A task with a past `dueDate` AND a recurrence rule might still be due today if the rule matches.

    // If the checkDate is before the task's original due date, it's not due yet by recurrence
    // unless the rule makes it due earlier (not typical for simple rules).
    if (task.dueDate != null) {
        DateTime taskDueDateWithoutTime = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
        if (checkDate.isBefore(taskDueDateWithoutTime) && type != null) {
            // If checking a date before its anchor `dueDate` and it has a recurrence rule,
            // it's only due if the rule explicitly makes it active before `dueDate` (complex)
            // or if `dueDate` itself is the first instance.
            // For simplicity, if `checkDate` is before `dueDate`, it's not due by recurrence.
            // This means `dueDate` acts as the first occurrence date for recurring tasks.
            return false;
        }
    }


    switch (type) {
      case 'daily':
        // If it's daily, and we've passed the initial checks (e.g., not before dueDate), it's due.
        return true;
      case 'weekly':
        final days = rule['days'] as List<dynamic>?; // e.g., [1, 3, 5] for Mon, Wed, Fri
        if (days == null || days.isEmpty) return false;
        // DateTime.weekday returns 1 for Monday, 7 for Sunday.
        final checkWeekday = checkDate.weekday;
        return days.any((day) => day is int && day == checkWeekday);
      case 'monthly':
        final dayOfMonth = rule['dayOfMonth'] as int?;
        if (dayOfMonth == null) return false;
        return checkDate.day == dayOfMonth;
      default:
        return false; // Unknown recurrence type
    }
  }

  /// Generates a list of upcoming due dates for a task, starting from a given date.
  /// This is more complex and might be a future addition.
  /// For now, this can be a placeholder.
  static List<DateTime> getUpcomingDueDates(Task task, DateTime startDate, {int count = 5}) {
    List<DateTime> upcomingDates = [];
    // Placeholder: actual implementation would iterate and use isTaskDueOnDate or similar logic
    // This would need careful handling of start dates, task.dueDate, and rule intervals.
    print("getUpcomingDueDates is a placeholder and not fully implemented.");
    return upcomingDates;
  }

  // You could add more specific helper functions, e.g.:
  // static bool _isDaily(Map<String, dynamic> rule) => rule['type'] == 'daily';
  // static bool _isWeeklyOnDate(Map<String, dynamic> rule, DateTime date) { ... }
  // static bool _isMonthlyOnDate(Map<String, dynamic> rule, DateTime date) { ... }
}
