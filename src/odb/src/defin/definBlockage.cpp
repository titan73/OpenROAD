// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2019-2025, The OpenROAD Authors

#include "definBlockage.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "definPolygon.h"
#include "odb/db.h"
#include "odb/dbShape.h"
#include "utl/Logger.h"

namespace odb {

void definBlockage::blockageRoutingBegin(const char* layer)
{
  _layer = _tech->findLayer(layer);
  _inst = nullptr;
  _slots = false;
  _fills = false;
  _except_pg_nets = false;
  _pushdown = false;
  _has_min_spacing = false;
  _has_effective_width = false;
  _min_spacing = 0;
  _effective_width = 0;

  if (_layer == nullptr) {
    _logger->warn(
        utl::ODB, 88, "error: undefined layer ({}) referenced", layer);
    ++_errors;
  }
}

void definBlockage::blockageRoutingComponent(const char* comp)
{
  _inst = _block->findInst(comp);

  if (_inst == nullptr) {
    _logger->warn(
        utl::ODB, 89, "error: undefined component ({}) referenced", comp);
    ++_errors;
  }
}

void definBlockage::blockageRoutingSlots()
{
  _slots = true;
}

void definBlockage::blockageRoutingFills()
{
  _fills = true;
}

void definBlockage::blockageRoutingExceptPGNets()
{
  _except_pg_nets = true;
}

void definBlockage::blockageRoutingPushdown()
{
  _pushdown = true;
}

void definBlockage::blockageRoutingMinSpacing(int spacing)
{
  _has_min_spacing = true;
  _min_spacing = spacing;
}

void definBlockage::blockageRoutingEffectiveWidth(int width)
{
  _has_effective_width = true;
  _effective_width = width;
}

void definBlockage::blockageRoutingRect(int x1, int y1, int x2, int y2)
{
  if (_layer == nullptr) {
    return;
  }

  x1 = dbdist(x1);
  y1 = dbdist(y1);
  x2 = dbdist(x2);
  y2 = dbdist(y2);
  dbObstruction* o
      = dbObstruction::create(_block, _layer, x1, y1, x2, y2, _inst);

  if (_pushdown) {
    o->setPushedDown();
  }

  if (_fills) {
    o->setFillObstruction();
  }

  if (_slots) {
    o->setSlotObstruction();
  }

  if (_has_min_spacing) {
    o->setMinSpacing(dbdist(_min_spacing));
  }

  if (_has_effective_width) {
    o->setEffectiveWidth(dbdist(_effective_width));
  }
}

void definBlockage::blockageRoutingPolygon(const std::vector<Point>& points)
{
  if (_layer == nullptr) {
    return;
  }

  definPolygon polygon(points);
  std::vector<Rect> R;
  polygon.decompose(R);

  std::vector<Rect>::iterator itr;

  for (itr = R.begin(); itr != R.end(); ++itr) {
    Rect& r = *itr;

    dbObstruction* o = dbObstruction::create(
        _block, _layer, r.xMin(), r.yMin(), r.xMax(), r.yMax(), _inst);
    if (_pushdown) {
      o->setPushedDown();
    }

    if (_fills) {
      o->setFillObstruction();
    }

    if (_except_pg_nets) {
      o->setExceptPGNetsObstruction();
    }

    if (_slots) {
      o->setSlotObstruction();
    }
    if (_has_min_spacing) {
      o->setMinSpacing(dbdist(_min_spacing));
    }

    if (_has_effective_width) {
      o->setEffectiveWidth(dbdist(_effective_width));
    }
  }
}

void definBlockage::blockageRoutingEnd()
{
}

void definBlockage::blockagePlacementBegin()
{
  _layer = nullptr;
  _inst = nullptr;
  _slots = false;
  _fills = false;
  _except_pg_nets = false;
  _pushdown = false;
  _soft = false;
  _max_density = 0.0;
}

void definBlockage::blockagePlacementComponent(const char* comp)
{
  _inst = _block->findInst(comp);

  if (_inst == nullptr) {
    _logger->warn(
        utl::ODB, 90, "error: undefined component ({}) referenced", comp);
    ++_errors;
  }
}

void definBlockage::blockagePlacementPushdown()
{
  _pushdown = true;
}

void definBlockage::blockagePlacementSoft()
{
  _soft = true;
}

void definBlockage::blockagePlacementMaxDensity(double max_density)
{
  if (max_density >= 0 && max_density <= 100) {
    _max_density = max_density;
  } else {
    _logger->warn(
        utl::ODB,
        91,
        "warning: Blockage max density {} not in [0, 100] will be ignored",
        max_density);
  }
}

void definBlockage::blockagePlacementRect(int x1, int y1, int x2, int y2)
{
  x1 = dbdist(x1);
  y1 = dbdist(y1);
  x2 = dbdist(x2);
  y2 = dbdist(y2);
  dbBlockage* b = dbBlockage::create(_block, x1, y1, x2, y2, _inst);

  if (_pushdown) {
    b->setPushedDown();
  }

  if (_soft) {
    b->setSoft();
  }

  if (_max_density > 0) {
    b->setMaxDensity(_max_density);
  }
}

void definBlockage::blockagePlacementEnd()
{
}

}  // namespace odb
