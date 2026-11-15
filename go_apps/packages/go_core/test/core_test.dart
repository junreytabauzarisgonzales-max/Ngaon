// Single entry point: one flutter_tester process for all go_core tests.
import 'package:flutter_test/flutter_test.dart';

import 'src/job_flow_tests.dart' as job_flow;
import 'src/mock_backend_tests.dart' as mock_backend;
import 'src/models_tests.dart' as models;
import 'src/network_tests.dart' as network;
import 'src/utils_tests.dart' as utils;

void main() {
  group('models (fixture round-trip)', models.main);
  group('utils', utils.main);
  group('job flow mappings', job_flow.main);
  group('network', network.main);
  group('mock backend', mock_backend.main);
}
