/* Authors: Lutong Wang and Bangqi Xu */
/*
 * Copyright (c) 2019, The Regents of the University of California
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the University nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma once

#include <memory>
#include <vector>

#include "frDesign.h"

namespace drt {
class drNet;
class drPatchWire;
class FlexDRWorker;
class gcNet;
class gcPin;

class FlexGCWorker
{
 public:
  // constructors
  FlexGCWorker(frTechObject* techIn,
               Logger* logger,
               RouterConfiguration* router_cfg,
               FlexDRWorker* drWorkerIn = nullptr);
  ~FlexGCWorker();
  // setters
  void setExtBox(const Rect& in);
  void setDrcBox(const Rect& in);
  bool setTargetNet(frBlockObject* in);
  gcNet* getTargetNet();
  void resetTargetNet();
  void addTargetObj(frBlockObject* in);
  void setTargetObjs(const std::set<frBlockObject*>& targetObjs);
  void setIgnoreDB();
  void setIgnoreMinArea();
  void setIgnoreLongSideEOL();
  void setIgnoreCornerSpacing();
  void setEnableSurgicalFix(bool in);
  void addPAObj(frConnFig* obj, frBlockObject* owner);
  // getters
  std::vector<std::unique_ptr<gcNet>>& getNets();
  gcNet* getNet(frNet* net);
  frDesign* getDesign() const;
  const std::vector<std::unique_ptr<frMarker>>& getMarkers() const;
  const std::vector<std::unique_ptr<drPatchWire>>& getPWires() const;
  // others
  void init(const frDesign* design);
  int main();
  void end();
  void clearPWires();
  // initialization from FlexPA, initPA0 --> addPAObj --> initPA1
  void initPA0(const frDesign* design);
  void initPA1();
  void updateDRNet(drNet* net);
  // used in rp_prep
  void checkMinStep(gcPin* pin);
  void updateGCWorker();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
struct MarkerId
{
  Rect box;
  frLayerNum lNum;
  frConstraint* con;
  std::set<frBlockObject*> srcs;
  bool operator<(const MarkerId& rhs) const
  {
    return std::tie(box, lNum, con, srcs)
           < std::tie(rhs.box, rhs.lNum, rhs.con, rhs.srcs);
  }
};
}  // namespace drt
