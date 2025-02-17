import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/modules/asset_viewer/providers/render_list.provider.dart';
import 'package:immich_mobile/modules/home/ui/asset_grid/asset_grid_data_structure.dart';
import 'package:immich_mobile/modules/home/ui/asset_grid/immich_asset_grid.dart';
import 'package:immich_mobile/modules/home/ui/asset_grid/immich_asset_grid_view.dart';
import 'package:immich_mobile/modules/map/models/map_page_event.model.dart';
import 'package:immich_mobile/shared/models/asset.dart';
import 'package:immich_mobile/shared/ui/drag_sheet.dart';
import 'package:immich_mobile/utils/color_filter_generator.dart';
import 'package:immich_mobile/utils/debounce.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPageBottomSheet extends StatefulHookConsumerWidget {
  final Stream mapPageEventStream;
  final StreamController bottomSheetEventSC;
  final bool selectionEnabled;
  final ImmichAssetGridSelectionListener selectionlistener;
  final bool isDarkTheme;

  const MapPageBottomSheet({
    super.key,
    required this.mapPageEventStream,
    required this.bottomSheetEventSC,
    required this.selectionEnabled,
    required this.selectionlistener,
    this.isDarkTheme = false,
  });

  @override
  AssetsInBoundBottomSheetState createState() =>
      AssetsInBoundBottomSheetState();
}

class AssetsInBoundBottomSheetState extends ConsumerState<MapPageBottomSheet> {
  // Non-State variables
  bool userTappedOnMap = false;
  RenderList? _cachedRenderList;
  int lastAssetOffsetInSheet = -1;
  late final DraggableScrollableController bottomSheetController;
  late final Debounce debounce;

  @override
  void initState() {
    super.initState();
    bottomSheetController = DraggableScrollableController();
    debounce = Debounce(
      const Duration(milliseconds: 200),
    );
  }

  @override
  Widget build(BuildContext context) {
    var isDarkMode = Theme.of(context).brightness == Brightness.dark;
    double maxHeight = MediaQuery.of(context).size.height;
    final isSheetScrolled = useState(false);
    final isSheetExpanded = useState(false);
    final assetsInBound = useState(<Asset>[]);
    final currentExtend = useState(0.1);

    void handleMapPageEvents(dynamic event) {
      if (event is MapPageAssetsInBoundUpdated) {
        assetsInBound.value = event.assets;
      } else if (event is MapPageOnTapEvent) {
        userTappedOnMap = true;
        lastAssetOffsetInSheet = -1;
        bottomSheetController.animateTo(
          0.1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linearToEaseOut,
        );
        isSheetScrolled.value = false;
      }
    }

    useEffect(
      () {
        final mapPageEventSubscription =
            widget.mapPageEventStream.listen(handleMapPageEvents);
        return mapPageEventSubscription.cancel;
      },
      [widget.mapPageEventStream],
    );

    void handleVisibleItems(ItemPosition start, ItemPosition end) {
      final renderElement = _cachedRenderList?.elements[start.index];
      if (renderElement == null) {
        return;
      }
      final rowOffset = renderElement.offset;
      if ((-start.itemLeadingEdge) != 0) {
        var columnOffset = -start.itemLeadingEdge ~/ 0.05;
        columnOffset = columnOffset < renderElement.totalCount
            ? columnOffset
            : renderElement.totalCount - 1;
        lastAssetOffsetInSheet = rowOffset + columnOffset;
        final asset = _cachedRenderList?.allAssets?[lastAssetOffsetInSheet];
        userTappedOnMap = false;
        if (!userTappedOnMap && isSheetExpanded.value) {
          widget.bottomSheetEventSC.add(
            MapPageBottomSheetScrolled(asset),
          );
        }
        if (isSheetExpanded.value) {
          isSheetScrolled.value = true;
        }
      }
    }

    void visibleItemsListener(ItemPosition start, ItemPosition end) {
      if (_cachedRenderList == null) {
        debounce.dispose();
        return;
      }
      debounce.call(() => handleVisibleItems(start, end));
    }

    Widget buildNoPhotosWidget() {
      const image = Image(
        image: AssetImage('assets/lighthouse.png'),
      );

      return isSheetExpanded.value
          ? Column(
              children: [
                const SizedBox(
                  height: 80,
                ),
                SizedBox(
                  height: 150,
                  width: 150,
                  child: isDarkMode
                      ? const InvertionFilter(
                          child: SaturationFilter(
                            saturation: -1,
                            child: BrightnessFilter(
                              brightness: -5,
                              child: image,
                            ),
                          ),
                        )
                      : image,
                ),
                const SizedBox(
                  height: 20,
                ),
                Text(
                  "map_zoom_to_see_photos".tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: Theme.of(context).textTheme.displayLarge?.color,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink();
    }

    void onTapMapButton() {
      if (lastAssetOffsetInSheet != -1) {
        widget.bottomSheetEventSC.add(
          MapPageZoomToAsset(
            _cachedRenderList?.allAssets?[lastAssetOffsetInSheet],
          ),
        );
      }
    }

    Widget buildDragHandle(ScrollController scrollController) {
      final textToDisplay = assetsInBound.value.isNotEmpty
          ? "${assetsInBound.value.length} photo${assetsInBound.value.length > 1 ? "s" : ""}"
          : "map_no_assets_in_bounds".tr();
      final dragHandle = Container(
        height: 75,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                const CustomDraggingHandle(),
                const SizedBox(height: 12),
                Text(
                  textToDisplay,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.displayLarge?.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(
                  color: Theme.of(context)
                      .textTheme
                      .displayLarge
                      ?.color
                      ?.withOpacity(0.5),
                ),
              ],
            ),
            if (isSheetExpanded.value && isSheetScrolled.value)
              Positioned(
                top: 5,
                right: 10,
                child: IconButton(
                  icon: Icon(
                    Icons.map_outlined,
                    color: Theme.of(context).textTheme.displayLarge?.color,
                  ),
                  iconSize: 20,
                  tooltip: 'Zoom to bounds',
                  onPressed: onTapMapButton,
                ),
              ),
          ],
        ),
      );
      return SingleChildScrollView(
        controller: scrollController,
        child: dragHandle,
      );
    }

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (DraggableScrollableNotification notification) {
        final sheetExtended = notification.extent > 0.2;
        isSheetExpanded.value = sheetExtended;
        currentExtend.value = notification.extent;
        if (!sheetExtended) {
          // reset state
          userTappedOnMap = false;
          lastAssetOffsetInSheet = -1;
          isSheetScrolled.value = false;
        }

        return true;
      },
      child: Stack(
        children: [
          DraggableScrollableSheet(
            controller: bottomSheetController,
            initialChildSize: 0.1,
            minChildSize: 0.1,
            maxChildSize: 0.55,
            snap: true,
            builder: (
              BuildContext context,
              ScrollController scrollController,
            ) {
              return Card(
                color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
                surfaceTintColor: Colors.transparent,
                elevation: 18.0,
                margin: const EdgeInsets.all(0),
                child: Column(
                  children: [
                    buildDragHandle(scrollController),
                    if (isSheetExpanded.value && assetsInBound.value.isNotEmpty)
                      ref
                          .watch(
                            renderListProvider(
                              assetsInBound.value,
                            ),
                          )
                          .when(
                            data: (renderList) {
                              _cachedRenderList = renderList;
                              final assetGrid = ImmichAssetGrid(
                                shrinkWrap: true,
                                renderList: renderList,
                                showDragScroll: false,
                                selectionActive: widget.selectionEnabled,
                                showMultiSelectIndicator: false,
                                listener: widget.selectionlistener,
                                visibleItemsListener: visibleItemsListener,
                              );

                              return Expanded(child: assetGrid);
                            },
                            error: (error, stackTrace) {
                              log.warning(
                                "Cannot get assets in the current map bounds ${error.toString()}",
                                error,
                                stackTrace,
                              );
                              return const SizedBox.shrink();
                            },
                            loading: () => const SizedBox.shrink(),
                          ),
                    if (isSheetExpanded.value && assetsInBound.value.isEmpty)
                      Expanded(
                        child: SingleChildScrollView(
                          child: buildNoPhotosWidget(),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: maxHeight * currentExtend.value,
            left: 0,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
              ),
              child: ColoredBox(
                color:
                    (widget.isDarkTheme ? Colors.grey[900] : Colors.grey[100])!,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(
                      fontSize: 6,
                      color: !widget.isDarkTheme
                          ? Colors.grey[900]
                          : Colors.grey[100],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: maxHeight * (0.14 + (currentExtend.value - 0.1)),
            right: 15,
            child: ElevatedButton(
              onPressed: () =>
                  widget.bottomSheetEventSC.add(const MapPageZoomToLocation()),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(12),
              ),
              child: const Icon(
                Icons.my_location,
                size: 22,
                fill: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
