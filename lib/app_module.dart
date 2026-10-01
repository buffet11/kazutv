import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazutv/core_module.dart';
import 'package:kazutv/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
