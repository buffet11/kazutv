class MenuRouteItem {
  const MenuRouteItem({required this.path});

  final String path;
}

class MenuRoute {
  const MenuRoute(this.menuList);

  final List<MenuRouteItem> menuList;

  String getPath(int index) => menuList[index].path;

  int indexForPath(String path) {
    final index = menuList.indexWhere(
      (item) =>
          path == '/tab${item.path}' ||
          path == '/tab${item.path}/' ||
          path.startsWith('/tab${item.path}/'),
    );
    return index < 0 ? 0 : index;
  }
}

const MenuRoute menu = MenuRoute([
  MenuRouteItem(path: '/popular'),
  MenuRouteItem(path: '/timeline'),
  MenuRouteItem(path: '/collect'),
  // 影视插在「追番」与「我的」之间。改这里 = 改所有 Tab 的下标：
  // 「我的」由 3 变 4。已确认 _handleSystemBack 只判断 `!= 0`，
  // 默认启动页设置按**路径**（`/tab/timeline/`）而非下标，所以不受影响。
  MenuRouteItem(path: '/movie'),
  MenuRouteItem(path: '/my'),
]);
