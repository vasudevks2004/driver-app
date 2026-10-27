class Resource<T> {
  const Resource({
    this.value,
    this.loading = false,
    this.error,
    this.updatedAt,
  });
  final T? value;
  final bool loading;
  final String? error;
  final DateTime? updatedAt;
  bool get available => value != null;
  Resource<T> fetching() =>
      Resource(value: value, loading: true, updatedAt: updatedAt);
  Resource<T> failed(String message) =>
      Resource(value: value, error: message, updatedAt: updatedAt);
  Resource<T> received(T next) =>
      Resource(value: next, updatedAt: DateTime.now());
}
