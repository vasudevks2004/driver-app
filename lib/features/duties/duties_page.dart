import 'package:flutter/material.dart';
import '../../design.dart';
import '../../driver_widgets.dart';
import '../workspace/controller.dart';
import '../workspace/ui.dart';

class DutiesPage extends StatelessWidget {
  const DutiesPage({super.key, required this.state});
  final DriverWorkspace state;
  @override
  Widget build(BuildContext context) {
    final resource = state.showCompleted ? state.completed : state.active;
    final page = resource.value;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pageHeading(
                  'Your duties',
                  'Everything you need for the road ahead.',
                ),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(
                          'Active (${state.active.value?.activeCount ?? '—'})',
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(
                          'Completed (${state.active.value?.completedCount ?? state.completed.value?.completedCount ?? '—'})',
                        ),
                      ),
                    ],
                    selected: {state.showCompleted},
                    onSelectionChanged: (values) => state.filter(values.first),
                  ),
                ),
                const SizedBox(height: 24),
                ResourceStatus(
                  resource: resource,
                  retry: () =>
                      state.loadDuties(completedOnly: state.showCompleted),
                  label: 'duties',
                ),
                if (page != null && page.items.isEmpty)
                  HireDEmptyState(
                    icon: state.showCompleted
                        ? Icons.task_alt_rounded
                        : Icons.route_outlined,
                    title: state.showCompleted
                        ? 'Your first completion is ahead.'
                        : 'No active duties yet.',
                    description: state.showCompleted
                        ? 'Completed duties stay here for your records.'
                        : 'New assignments will appear here after HireD assigns a duty.',
                  ),
              ],
            ),
          ),
        ),
        if (page != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: page.items.length,
              itemBuilder: (context, index) {
                final duty = page.items[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: DutyCard(
                      duty: duty.toJson(),
                      onOpen: () => state.select(duty.id),
                    ),
                  ),
                );
              },
            ),
          ),
        if (page?.nextCursor != null)
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: OutlinedButton(
                onPressed: resource.loading
                    ? null
                    : () => state.loadDuties(
                        completedOnly: state.showCompleted,
                        more: true,
                      ),
                child: const Text('Load more duties'),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
