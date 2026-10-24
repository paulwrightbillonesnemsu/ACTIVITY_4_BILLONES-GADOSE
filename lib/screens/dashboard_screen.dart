import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_card.dart';
import 'activity_details_screen.dart';

/// No local UI state of its own -> StatelessWidget. It simply reflects
/// whatever is currently in AppStateProvider.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // `watch` subscribes this widget to rebuilds whenever the provider
    // calls notifyListeners() (e.g. from the Settings theme toggle).
    final appState = context.watch<AppStateProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // ---- Top bar --------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dashboard_rounded,
                        color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => appState.toggleTheme(),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 29,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 15,
                      color: isDark ? Colors.white70 : AppColors.textGray,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ---- Greeting ---------------------------------------------------
            Text(
              'Hello! ${appState.userName}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your Flutter laboratory activities in one place.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textWhiteSoft : AppColors.textGray,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Laboratory Activities',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showCreateActivityDialog(context, appState),
                  tooltip: 'Create activity',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ---- Activity list ------------------------------------------
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: appState.activities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final activity = appState.activities[index];
                  return ActivityCard(
                    activity: activity,
                    onViewActivity: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ActivityDetailsScreen(activity: activity),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateActivityDialog(
    BuildContext context,
    AppStateProvider appState,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateActivityDialog(appState: appState),
    );
  }
}

class _CreateActivityDialog extends StatefulWidget {
  final AppStateProvider appState;

  const _CreateActivityDialog({required this.appState});

  @override
  State<_CreateActivityDialog> createState() => _CreateActivityDialogState();
}

class _CreateActivityDialogState extends State<_CreateActivityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _textController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create activity'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Activity name'),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an activity name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _textController,
                decoration: const InputDecoration(labelText: 'Activity text'),
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter activity text'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              widget.appState.addActivity(
                title: _titleController.text,
                text: _textController.text,
              );
              Navigator.of(context).pop();
            },
            child: const Text('Create'),
          ),
        ],
      );
}
