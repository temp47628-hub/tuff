angular.module('gaugesScreen', [])
.controller('GaugesScreenController', function($scope, $window, $sce) {
  var units = { uiUnitConsumptionRate: "metric", uiUnitDate: "ger", uiUnitEnergy: "metric", uiUnitLength: "metric", uiUnitPower: "hp", uiUnitPressure: "bar", uiUnitTemperature: "c", uiUnitTorque: "metric", uiUnitVolume: "l", uiUnitWeight: "kg" };
  $scope.data = {};

  let lastSecondUpdate = 0, prevResetTrip = null, tripOffset = 0, lastSlowUpdate = 0, secondsCounter = 0;
  let lastButtonFan = null, lastHeated1 = null, lastHeated2 = null;
  let fanOverrideUntil = 0, seatOverrideUntil = 0;
  let mGearBoxes = [], mGearTexts = [], mGearCount = 0;
  let lastGaugesMenu = null;

  $window.setup = (setupData) => {
    for(let dk in setupData){
      if(typeof dk == "string" && dk.startsWith("uiUnit")){
        units[dk] = setupData[dk];
      }
    }
    vueEventBus.emit('SettingsChanged', {values:units})

    $scope.data.speedUnit = units.uiUnitLength=="metric"?"km/h":"mph";

    if(units.uiUnitConsumptionRate == "metric"){
      $scope.data.consumptionUnit = "l/100km"
    }else{
      $scope.data.consumptionUnit = "mpg"
    }
  }

  (function preload() {
    $window.preloadedImages = [];
    ['avg.png', 'door.png', 'door_FL.png', 'door_FR.png', 'door_RL.png', 'door_RR.png', 'fuel.png', 'high_watertemp.png', 'hood.png', 'lowfuel.png', 'trunk.png'].forEach(s => {
      let i = new Image(); i.src = s; $window.preloadedImages.push(i);
    });
  })();

  $window.updateData = (data) => {
    $scope.$evalAsync(function() {
      const e = data.electrics, env = data.customModules.environmentData, eng = data.customModules.combustionEngineData;
      const els = { top: document.querySelector(".toptext"), l2: document.querySelector(".line2"), rng: document.querySelector(".range"), tmp: document.querySelector(".temp"), f: document.getElementById('fuel_icon'), w: document.getElementById('warning_symbol'), wb: document.getElementById('warning_symbol_bottom') };
      const now = Date.now();

      const isM  = units.uiUnitLength === "metric";

      let tempEnv = UiUnits.temperature(env.temperatureEnv);
      const tUnit = tempEnv.unit;

      //CLIMATE START

      const ctx = e.hvac_context || 0;
      const isFanActive = ctx === 1;
      const isSeat1Active = ctx === 2;
      const isSeat2Active = ctx === 3;
      const isAirflow1Active = ctx === 4;
      const isAirflow2Active = ctx === 5;

      // Setpoints arrive from the vehicle in Celsius; LO/HI thresholds stay in C.
      const getC = (v) => {
        if (v <= 16) return "LO";
        if (v >= 28) return "HI";
        let t = UiUnits.temperature(v);
        return units.uiUnitTemperature === "f" ? Math.floor(t.val).toString() : t.val.toFixed(1);
      };

      [1, 2].forEach(i => {
        if ((e.button_econ || 0) === 2) {
          $scope.data["climateTemp" + i] = "OFF";
          $scope.data["climateTempUnit" + i] = "";
          return;
        }
        const seatActive = i === 1 ? isSeat1Active : isSeat2Active;
        const airflowActive = i === 1 ? isAirflow1Active : isAirflow2Active;

        if (seatActive) {
          $scope.data["climateTemp" + i] = e["button_heatedseat" + i] || 0;
          $scope.data["climateTempUnit" + i] = "";
        } else if (airflowActive) {
          $scope.data["climateTemp" + i] = (e["button_airflow" + i] === 0 ? "auto" : e["button_airflow" + i]) || 0;
          $scope.data["climateTempUnit" + i] = "";
        } else if (isFanActive) {
          $scope.data["climateTemp" + i] = e.button_fan || 0;
          $scope.data["climateTempUnit" + i] = "";
        } else {
          const val = getC(i === 1 ? e.tempLeft : e.tempRight);
          $scope.data["climateTemp" + i] = val;
          $scope.data["climateTempUnit" + i] = (val !== "LO" && val !== "HI") ? tUnit : "";
        }
      });

      //CLIMATE END

      els.top.style.transform = "scaleX(0.7)";
      let song = e.audi6_currentSongName || "";
      $scope.data.toptext = song.length > 18 ? song.substring(0, 15) + "..." : song;
      if (e.tcsoff == 1) { els.top.style.transform = "scaleX(1)"; $scope.data.toptext = "ESP OFF"; }
      els.w.style.backgroundImage = e.lowfuel == 1 ? "url('lowfuel.png')" : "";
      if (e.lowfuel == 1) $scope.data.toptext = "";

      const inMMode = typeof e.gear === 'string' && e.gear.includes('M');
      const inSMode = !inMMode && !['P','R','N','D'].includes(e.gear) && !e.manualShifterEnabled;

      if (inMMode) {
        // Hide all PRNDS elements
        $scope.data.gearNumber = "";
        ['P', 'R', 'N', 'D', 'S'].forEach(g => {
          const el = document.querySelector(".gear" + g);
          if (el) el.style.display = "none";
          $scope.data["gear" + g + "text"] = "";
        });

        const maxGears = e.maxGearIndex || 6;
        const currentGear = parseInt(e.gear.replace(/\D/g, '')) || 0;

        // Recreate elements if gear count changed
        if (mGearCount !== maxGears) {
          mGearBoxes.forEach(el => el.remove());
          mGearTexts.forEach(el => el.remove());
          mGearBoxes = []; mGearTexts = [];

          const gaugeDiv = document.querySelector('.gauge');
          for (let i = 1; i <= maxGears; i++) {
            const box = document.createElement('div');
            box.style.cssText = 'position:absolute;bottom:225px;width:24px;height:35px;background-color:#ff0000;z-index:100;display:none;transition:right 0.3s ease;';
            gaugeDiv.appendChild(box);
            mGearBoxes.push(box);

            const txt = document.createElement('div');
            txt.style.cssText = 'position:absolute;bottom:230px;width:210px;height:25px;font-family:AUDImmiBasic;font-size:40px;text-align:left;line-height:25px;z-index:101;color:#ff0000;transition:right 0.3s ease;';
            txt.textContent = i.toString();
            gaugeDiv.appendChild(txt);
            mGearTexts.push(txt);
          }
          mGearCount = maxGears;
        }

        // Position centered, descending order (highest gear left, 1 right)
        const stripW = maxGears * 24;
        const margin = (180 - stripW) / 2;
        const startRight = 16 + Math.max(margin, 0);

        for (let i = 0; i < maxGears; i++) {
          const gearNum = i + 1;
          const boxRight = startRight + (gearNum - 1) * 24;
          mGearBoxes[i].style.right = boxRight + 'px';
          mGearTexts[i].style.right = (boxRight - 192) + 'px';
          mGearTexts[i].style.display = '';

          if (gearNum === currentGear) {
            mGearBoxes[i].style.display = 'block';
            mGearTexts[i].style.color = 'black';
          } else {
            mGearBoxes[i].style.display = 'none';
            mGearTexts[i].style.color = '#ff0000';
          }
        }
      } else {
        // Hide manual gear elements
        mGearBoxes.forEach(el => { el.style.display = 'none'; });
        mGearTexts.forEach(el => { el.style.display = 'none'; });

        // Show PRNDS
        const gearOff = inSMode ? 30 : 0;
        const boxR = { P: 142, R: 118, N: 94, D: 70, S: 46 };
        const txtR = { P: -50, R: -74, N: -98, D: -122, S: -146 };

        $scope.data.gearNumber = "";
        ['P', 'R', 'N', 'D', 'S'].forEach(g => {
          const el = document.querySelector(".gear" + g), txt = document.querySelector(".gear" + g + "text");
          if (!el || !txt) return;
          el.style.display = "none";
          el.style.right = (boxR[g] + gearOff) + 'px';
          txt.style.right = (txtR[g] + gearOff) + 'px';
          if (!e.manualShifterEnabled) {
            $scope.data["gear" + g + "text"] = g;
            txt.style.color = "#ff0000";
            if (e.gear === g || (g === 'S' && !['P','R','N','D'].includes(e.gear))) {
              el.style.display = "block"; txt.style.color = "black";
              if (g === 'S') $scope.data.gearNumber = (typeof e.gear === "string") ? (e.gear.match(/\d+$/) || [""])[0] : "";
            }
          }
        });
      }

      let anyOpen = false;
      [...["FL", "FR", "RL", "RR"].map(d => ({ k: `door_${d}_coupler_notAttached`, id: `door_${d}`, i: `door_${d}.png` })), { k: "hoodLatchCoupler_notAttached", id: "hood", i: "hood.png" }, { k: "trunkCoupler_notAttached", id: "trunk", i: "trunk.png" }]
      .forEach(item => {
        const el = document.getElementById(item.id);
        if (e[item.k] === 1) { if (el) el.style.backgroundImage = `url('${item.i}')`; anyOpen = true; }
        else if (el) el.style.backgroundImage = "";
      });
      const dMain = document.getElementById("door");
      if (dMain) dMain.style.backgroundImage = anyOpen ? "url('door.png')" : "";

      const isPriority = anyOpen || e.high_watertemp == 1;
      if (isPriority) {
        els.l2.style.display = els.rng.style.display = els.tmp.style.display = "none";
        els.f.style.backgroundImage = "";
        els.wb.style.backgroundImage = e.high_watertemp == 1 ? "url('high_watertemp.png')" : "";
      } else {
        els.l2.style.display = els.rng.style.display = els.tmp.style.display = "";
        els.wb.style.backgroundImage = "";
        const iconMap = { 1: "fuel.png", 2: "avg.png", 3: "", 4: "avg.png" };
        const icon = iconMap[e.gaugesMenu];
        els.f.style.backgroundImage = icon ? `url('${icon}')` : "";
      }

      if (e.gaugesMenu !== lastGaugesMenu) { lastSlowUpdate = 0; lastGaugesMenu = e.gaugesMenu; }

      if (now - lastSlowUpdate >= 333) {
        lastSlowUpdate = now;
        if (now - lastSecondUpdate >= 1000) {
          secondsCounter++; lastSecondUpdate = now;
          const d = new Date();
          $scope.data.date = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
        }
        $scope.data.time = env.time;

        const distFac = isM ? 0.001 : 0.0006215;      // metres -> km / miles
        const distUnit = isM ? "km" : "mi";
        if (prevResetTrip !== null && e.resetTrip !== prevResetTrip) tripOffset = e.odometer || 0;
        prevResetTrip = e.resetTrip;

        const tVal = Math.max((e.odometer || 0) - tripOffset, 0) * distFac;
        $scope.data.trip = Math.min(tVal, 9999).toFixed(1);
        $scope.data.odo = Math.min((e.audi6_odo || 0) * distFac, 999999).toFixed(0);
        $scope.data.distanceUnit = distUnit;

        if (tempEnv.val.toFixed(1) > 99.9 || tempEnv.val.toFixed(1) < -99.9) {
          $scope.data.temp = "---" + tempEnv.unit;
        } else {
          $scope.data.temp = (tempEnv.val >= 0 ? "+" : "") + tempEnv.val.toFixed(1) + tempEnv.unit;
        }

        if (!isPriority) {
          let avgConso = UiUnits.consumptionRate(eng.averageFuelConsumption * 1e-5);
          let curConso = UiUnits.consumptionRate(eng.currentFuelConsumption * 1e-5);
          const menus = {
            1: { v: eng.remainingRange * (isM ? 1 : 0.6215), u: distUnit, f: 0 },
            2: { v: avgConso.val === "n/a" ? null : avgConso.val, u: avgConso.unit, f: 1 },
            3: { v: curConso.val === "n/a" ? null : curConso.val, u: curConso.unit, f: 1 },
            4: { v: tVal / (secondsCounter / 3600 || 1), u: isM ? "km/h" : "mph", f: 1 }
          };
          const m = menus[e.gaugesMenu];
          if (m) {
            const txt = (typeof m.v === "number" && isFinite(m.v)) ? m.v.toFixed(m.f) : "---";
            $scope.data.range = $sce.trustAsHtml(txt + `<span class="unit">${m.u}</span>`);
          }
        }
      }
    });
  };
});