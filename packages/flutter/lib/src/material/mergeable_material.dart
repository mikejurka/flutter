// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' show lerpDouble;

/// A class that abstracts over a Material slice and a Material gap.
///
/// All [MergeableMaterialItem] objects need a [LocalKey].
abstract class MergeableMaterialItem {
  MergeableMaterialItem(this.key) {
    assert(key != null);
  }

  final LocalKey key;
}

/// A class that can be used as a child to [MergeableMaterial]. It is a slice
/// of [Material] that animates merging with other slices.
///
/// All [MaterialSlice] objects need a [LocalKey].
class MaterialSlice extends MergeableMaterialItem {
  /// Creates a slice of [Material] that's mergeable within a
  /// [MergeableMaterial].
  MaterialSlice({
    LocalKey key,
    this.child
  }) : super(key);

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  String toString() {
    return 'MergeableSlice(key: $key, child: $child)';
  }
}

/// A class that represents a gap within [MergeableMaterial].
///
/// All [MaterialGap] objects need a [LocalKey].
class MaterialGap extends MergeableMaterialItem {
  /// Creates a Material gap with a given size.
  MaterialGap({
    LocalKey key,
    this.size: 16.0
  }) : super(key);

  /// The size of the gap, irrespective of the axis used.
  final double size;

  @override
  String toString() {
    return 'MaterialGap(key: $key, child: $size)';
  }
}

/// A widget useful for animating the merging and separating of [Material]
/// slices. The widget takes [MergeableMaterialItem] children, uses a block
/// layout algorithm, and separates [MaterialSlice] wherever it sees a
/// [MaterialGap]. Animations work by figuring out where new gaps were
/// added/removed when the widget gets rebuilt by checking the children's keys,
/// which is why keys on children are mandatory.
///
/// The addition of extra slices is not animated and neither is the adding of
/// any extra items at the end of the children list.
class MergeableMaterial extends StatefulWidget {
  /// Creates a mergeable Material list of items.
  MergeableMaterial({
    Key key,
    this.mainAxis: Axis.vertical,
    this.elevation: 2,
    this.children: const <MergeableMaterialItem>[]
  }) : super(key: key);

  /// The children of the [MergeableMaterial].
  final List<MergeableMaterialItem> children;

  /// The main layout axis.
  final Axis mainAxis;

  /// The elevation of all the [Material] slices.
  final int elevation;

  @override
  String toString() {
    return 'MergeableMaterial('
      'key: $key, mainAxis: $mainAxis, '
      'elevation: $elevation, children: $children'
    ')';
  }

  @override
  _MergeableMaterialState createState() {
    return new _MergeableMaterialState();
  }
}

class _AnimationTuple {
  _AnimationTuple({
    this.controller,
    this.startAnimation,
    this.endAnimation,
    this.gapAnimation,
    this.gapStart: 0.0
  });

  final AnimationController controller;
  final CurvedAnimation startAnimation;
  final CurvedAnimation endAnimation;
  final CurvedAnimation gapAnimation;
  double gapStart;
}

class _MergeableMaterialState extends State<MergeableMaterial> {
  List<MergeableMaterialItem> _children;
  Map<LocalKey, _AnimationTuple> _animationTuples;

  void _initGap(MaterialGap gap) {
    final AnimationController controller = new AnimationController(
      duration: kThemeAnimationDuration
    );

    final CurvedAnimation startAnimation = new CurvedAnimation(
      parent: controller,
      curve: Curves.ease,
      reverseCurve: Curves.ease
    );
    final CurvedAnimation endAnimation = new CurvedAnimation(
      parent: controller,
      curve: Curves.ease,
      reverseCurve: Curves.ease
    );

    startAnimation.addListener(_handleTick);
    endAnimation.addListener(_handleTick);

    final CurvedAnimation gapAnimation = new CurvedAnimation(
      parent: controller,
      curve: Curves.ease,
      reverseCurve: Curves.ease
    );

    gapAnimation.addListener(_handleTick);

    _animationTuples[gap.key] = new _AnimationTuple(
      controller: controller,
      startAnimation: startAnimation,
      endAnimation: endAnimation,
      gapAnimation: gapAnimation
    );
  }

  @override
  void initState() {
    super.initState();
    _children = new List<MergeableMaterialItem>.from(config.children);
    _animationTuples = new Map<LocalKey, _AnimationTuple>();

    for (int i = 0; i < _children.length; i += 1) {
      if (_children[i] is MaterialGap) {
        _initGap(_children[i]);
        _animationTuples[_children[i].key].controller.value = 1.0; // Gaps must be wide when first built.
      }
    }
    assert(_debugGapsAreValid(_children));
  }

  @override
  void dispose() {
    for (MergeableMaterialItem child in _children) {
      if (child is MaterialGap) {
        _animationTuples[child.key].controller.dispose();
      }
    }
    super.dispose();
  }

  void _handleTick() {
    setState(() {
      // The animation's state is our build state, and it changed already.
    });
  }

  bool _debugConsecutiveGaps(List<MergeableMaterialItem> children) {
    for (int i = 0; i < config.children.length - 1; i += 1) {
      if (config.children[i] is MaterialGap &&
          config.children[i + 1] is MaterialGap)
        return true;
    }
    return false;
  }

  bool _debugGapsAreValid(List<MergeableMaterialItem> children) {
    // Check for consecutive gaps.
    if (_debugConsecutiveGaps(children))
      return false;

    // First and last children must not be gaps.
    if (children.isNotEmpty) {
      if (children.first is MaterialGap || children.last is MaterialGap)
        return false;
    }

    return true;
  }

  void _insertChild(int index, MergeableMaterialItem child) {
    _children.insert(index, child);

    if (child is MaterialGap)
      _initGap(child);
  }

  void _removeChild(int index) {
    MergeableMaterialItem child = _children.removeAt(index);

    if (child is MaterialGap)
      _animationTuples[child.key] = null;
  }

  bool _closingGap(int index) {
    if (index < _children.length - 1 && _children[index] is MaterialGap) {
      return _animationTuples[_children[index].key].controller.status ==
          AnimationStatus.reverse;
    }

    return false;
  }

  @override
  void didUpdateConfig(MergeableMaterial oldConfig) {
    final Set<LocalKey> oldKeys = oldConfig.children.map(
      (MergeableMaterialItem child) => child.key
    ).toSet();
    final Set<LocalKey> newKeys = config.children.map(
      (MergeableMaterialItem child) => child.key
    ).toSet();
    final Set<LocalKey> newOnly = newKeys.difference(oldKeys);
    final Set<LocalKey> oldOnly = oldKeys.difference(newKeys);

    final List<MergeableMaterialItem> newChildren = config.children;
    int i = 0;
    int j = 0;

    assert(_debugGapsAreValid(newChildren));

    while (j < _children.length) {
      if (_children[j] is MaterialGap &&
          _animationTuples[_children[j].key].controller.status
          == AnimationStatus.dismissed) {
        _removeChild(j);
      } else {
        j += 1;
      }
    }

    j = 0;

    while (i < newChildren.length && j < _children.length) {
      if (newOnly.contains(newChildren[i].key) ||
          oldOnly.contains(_children[j].key)) {
        final int startNew = i;
        final int startOld = j;

        // Skip new keys.
        while (newOnly.contains(newChildren[i].key))
          i += 1;

        // Skip old keys.
        while (oldOnly.contains(_children[j].key) || _closingGap(j))
          j += 1;

        final int newLength = i - startNew;
        final int oldLength = j - startOld;

        if (newLength > 0) {
          if (oldLength > 1 ||
              oldLength == 1 && _children[startOld] is MaterialSlice) {
            if (newLength == 1 && newChildren[startNew] is MaterialGap) {
              // Shrink all gaps into the size of the new one.
              double gapSizeSum = 0.0;

              while (startOld < j) {
                if (_children[startOld] is MaterialGap) {
                  MaterialGap gap = _children[startOld];
                  gapSizeSum += gap.size;
                }

                _removeChild(startOld);
                j -= 1;
              }

              _insertChild(startOld, newChildren[startNew]);
              _animationTuples[newChildren[startNew].key]
                ..gapStart = gapSizeSum
                ..controller.forward();

              j += 1;
            } else {
              // No animation if replaced items are more than one.
              for (int k = 0; k < oldLength; k += 1)
                _removeChild(startOld);
              for (int k = 0; k < newLength; k += 1)
                _insertChild(startOld + k, newChildren[startNew + k]);

              j += newLength - oldLength;
            }
          } else if (oldLength == 1) {
            final double gapSize = _getGapSize(startOld);

            _removeChild(startOld);

            for (int k = 0; k < newLength; k += 1)
              _insertChild(startOld + k, newChildren[startNew + k]);

            j += newLength - 1;
            double gapSizeSum = 0.0;

            for (int k = startNew; k < i; k += 1) {
              if (newChildren[k] is MaterialGap) {
                MaterialGap gap = newChildren[k];

                gapSizeSum += gap.size;
              }
            }

            // All gaps get proportional sizes of the original gap and they will
            // animate to their actual size.
            for (int k = startNew; k < i; k += 1) {
              if (newChildren[k] is MaterialGap) {
                MaterialGap gap = newChildren[k];

                _animationTuples[gap.key].gapStart = gapSize * gap.size /
                    gapSizeSum;
                _animationTuples[gap.key].controller
                  ..value = 0.0
                  ..forward();
              }
            }
          } else {
            // Grow gaps.
            for (int k = 0; k < newLength; k += 1) {
              _insertChild(startOld + k, newChildren[startNew + k]);

              if (newChildren[startNew + k] is MaterialGap) {
                MaterialGap gap = newChildren[startNew + k];
                _animationTuples[gap.key].controller.forward();
              }
            }

            j += newLength;
          }
        } else {
          // If more than a gap disappeared, just remove slices and shrink gaps.
          if (oldLength > 1 ||
              oldLength == 1 && _children[startOld] is MaterialSlice) {
            double gapSizeSum = 0.0;

            while (startOld < j) {
              if (_children[startOld] is MaterialGap) {
                MaterialGap gap = _children[startOld];
                gapSizeSum += gap.size;
              }

              _removeChild(startOld);
              j -= 1;
            }

            if (gapSizeSum != 0.0) {
              MaterialGap gap = new MaterialGap(
                key: new UniqueKey(),
                size: gapSizeSum
              );
              _insertChild(startOld, gap);
              _animationTuples[gap.key].gapStart = 0.0;
              _animationTuples[gap.key].controller
                ..value = 1.0
                ..reverse();

              j += 1;
            }
          } else if (oldLength == 1) {
            // Shrink gap.
            MaterialGap gap = _children[startOld];
            _animationTuples[gap.key].gapStart = 0.0;
            _animationTuples[gap.key].controller.reverse();
          }
        }
      } else {
        _children[j] = newChildren[i];

        i += 1;
        j += 1;
      }
    }

    // Handle remaining items.
    while (j < _children.length)
      _removeChild(j);
    while (i < newChildren.length) {
      _insertChild(j, newChildren[i]);

      i += 1;
      j += 1;
    }
  }

  BorderRadius _getBorderRadius(int index) {
    final Radius cardRadius = kMaterialEdges[MaterialType.card].topLeft;

    Radius startRadius = Radius.zero;
    Radius endRadius = Radius.zero;

    if (index > 0 && _children[index - 1] is MaterialGap) {
      startRadius = Radius.lerp(
        Radius.zero,
        cardRadius,
        _animationTuples[_children[index - 1].key].startAnimation.value
      );
    }
    if (index < _children.length - 2 && _children[index + 1] is MaterialGap) {
      endRadius = Radius.lerp(
        Radius.zero,
        cardRadius,
        _animationTuples[_children[index + 1].key].endAnimation.value
      );
    }

    if (config.mainAxis == Axis.vertical) {
      return new BorderRadius.vertical(
        top: index == 0 ? cardRadius : startRadius,
        bottom: index == _children.length - 1 ? cardRadius : endRadius
      );
    } else {
      return new BorderRadius.horizontal(
        left: index == 0 ? cardRadius : startRadius,
        right: index == _children.length - 1 ? cardRadius : endRadius
      );
    }
  }

  double _getGapSize(int index) {
    MaterialGap gap = _children[index];

    return lerpDouble(
      _animationTuples[gap.key].gapStart,
      gap.size,
      _animationTuples[gap.key].gapAnimation.value
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = <Widget>[];

    for (int i = 0; i < _children.length; i += 1) {
      if (_children[i] is MaterialGap) {
        widgets.add(
          new SizedBox(
            width: config.mainAxis == Axis.horizontal ? _getGapSize(i) : null,
            height: config.mainAxis == Axis.vertical ? _getGapSize(i) : null
          )
        );
      } else {
        MaterialSlice slice = _children[i];

        widgets.add(
          new Container(
            decoration: new BoxDecoration(
              backgroundColor: Theme.of(context).cardColor,
              borderRadius: _getBorderRadius(i),
              shape: BoxShape.rectangle
            ),
            child: new Material(
              type: MaterialType.transparency,
              child: slice.child
            )
          )
        );
      }
    }

    return new _MergeableMaterialBlockBody(
      mainAxis: config.mainAxis,
      boxShadows: kElevationToShadow[config.elevation],
      items: _children,
      children: widgets
    );
  }
}

class _MergeableMaterialBlockBody extends BlockBody {
  _MergeableMaterialBlockBody({
    List<Widget> children,
    Axis mainAxis: Axis.vertical,
    this.items,
    this.boxShadows
  }) : super(children: children, mainAxis: mainAxis);

  List<MergeableMaterialItem> items;
  List<BoxShadow> boxShadows;

  @override
  RenderBlock createRenderObject(BuildContext context) {
    return new _MergeableMaterialRenderBlock(
      mainAxis: mainAxis,
      boxShadows: boxShadows,
      items: items
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderBlock renderObject) {
    _MergeableMaterialRenderBlock materialRenderBlock = renderObject;
    materialRenderBlock
      ..mainAxis = mainAxis
      ..boxShadows = boxShadows
      ..items = items;
  }
}

class _MergeableMaterialRenderBlock extends RenderBlock {
  _MergeableMaterialRenderBlock({
    List<RenderBox> children,
    Axis mainAxis: Axis.vertical,
    this.items,
    this.boxShadows
  }) : super(children: children, mainAxis: mainAxis);

  List<MergeableMaterialItem> items;
  List<BoxShadow> boxShadows;

  void _paintShadows(Canvas canvas, Rect rect) {
    for (BoxShadow boxShadow in boxShadows) {
      final Paint paint = new Paint()
        ..color = boxShadow.color
        ..maskFilter = new MaskFilter.blur(BlurStyle.normal, boxShadow.blurSigma);
      // TODO(dragostis): Once shadow performance is better, shadows should be
      // redrawn on each interpolated rounded rectangle.
      canvas.drawRRect(kMaterialEdges[MaterialType.card].toRRect(rect), paint);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox child = firstChild;

    for (int i = 0; i < items.length; i += 1) {
      final BlockParentData childParentData = child.parentData;
      final Rect rect = (childParentData.offset + offset) & child.size;
      if (!(items[i] is MaterialGap))
        _paintShadows(context.canvas, rect);
      child = childParentData.nextSibling;
    }

    defaultPaint(context, offset);
  }
}
