library boot.os.tools.pool;

import 'package:pool/pool.dart';

typedef PoolTask<T> = Future<T> Function();

Future<List<T>> runTasksWithMaxConcurrency<T>(
    int maxTaskConcurrency, List<PoolTask<T>> tasks) async {
  final pool = Pool(maxTaskConcurrency);
  return await Future.wait(
      tasks.map((task) => pool.withResource(() => task())));
}