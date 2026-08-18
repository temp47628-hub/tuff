angular.module('gaugesScreen', [])
.controller('GaugesScreenController', function($scope, $window, $sce) {
  var units = {
    uiUnitConsumptionRate: "metric", uiUnitDate: "ger", uiUnitEnergy: "metric", uiUnitLength: "metric",
    uiUnitPower: "hp", uiUnitPressure: "bar", uiUnitTemperature: "c", uiUnitTorque: "metric",
    uiUnitVolume: "l", uiUnitWeight: "kg"
  };

  $scope.data = {};
  let secondsCounter = 0, prevResetTrip = null, tripOffset = 0, latestData = null;
  let lastClockTick = 0;
  
  // Logic state variables for overrides
  let lastButtonFan = null, lastHeated1 = null, lastHeated2 = null;
  let fanOverrideUntil = 0, seatOverrideUntil = 0;
  let lastGaugesMenu = null;
  
  // Buffering raw strings instead of SCE objects to prevent security context errors
  let displayBuffer = { speedVal: "0", speedUnit: "", rangeVal: "0", rangeUnit: "" };
  
  // Manual gear mode elements
  let mGearBoxes = [], mGearTexts = [], mGearCount = 0;
  
  // --- Bootscreen state ---
  let lastBootscreenState = null;
  let bootscreenEnabled = false;

  const setBootscreen = (ignition) => {
    if (!bootscreenEnabled) return;
    const bootscreen = document.getElementById('bootscreen');
    const gaugeRoot  = document.querySelector('.gauge');
    if (!bootscreen || !gaugeRoot) return;

    const shouldShow = ignition < 2;
    if (shouldShow === lastBootscreenState) return;

    bootscreen.classList.toggle('fadein',  shouldShow);
    bootscreen.classList.toggle('fadeout', !shouldShow);

    Array.from(gaugeRoot.children).forEach(child => {
      if (child.id === 'bootscreen') return;
      if (shouldShow) {
        Object.assign(child.style, { opacity: '0', visibility: 'hidden', transition: 'opacity 0.5s ease-in-out' });
      } else {
        setTimeout(() => {
          Object.assign(child.style, { visibility: 'visible', opacity: '1' });
          setTimeout(() => { child.style.transition = ''; }, 600);
        }, 400);
      }
    });

    lastBootscreenState = shouldShow;
  };
  // --- End Bootscreen ---

  const els = {
    toptext: document.querySelector(".toptext"),
    gears: {
      P: document.querySelector(".gearP"), R: document.querySelector(".gearR"),
      N: document.querySelector(".gearN"), D: document.querySelector(".gearD"), S: document.querySelector(".gearS")
    },
    gearText: document.querySelector(".gear"),
    gearNumDiv: document.querySelector(".gearNumber"),
    line1: document.querySelector(".line1"),
    line3: document.querySelector(".line3"),
    range: document.querySelector(".range"),
    temp: document.querySelector(".temp"),
    speedVal: document.querySelector(".speedVal"),
    warningCenter: document.querySelector(".warningCenter"),
    fuelIcon: document.getElementById('fuel_icon'),
    warning: document.getElementById('warning_symbol'),
    warnBottom: document.getElementById('warning_symbol_bottom'),
    doorMain: document.getElementById("door")
  };

  $window.setup = (setupData) => {
    for (let dk in setupData) if (dk.startsWith("uiUnit")) units[dk] = setupData[dk];
    vueEventBus.emit('SettingsChanged', {values:units})

    $scope.data.speedUnit = units.uiUnitLength=="metric"?"km/h":"mph";

    if(units.uiUnitConsumptionRate == "metric"){
      $scope.data.consumptionUnit = "l/100km"
    }else{
      $scope.data.consumptionUnit = "mpg"
    }
    if (setupData.bootscreenImage) {
      bootscreenEnabled = true;
      const el = document.getElementById('bootscreen');
      if (el) el.style.backgroundImage = `url('${setupData.bootscreenImage}')`;
    }
  };

  (function preload() {
    ['avg.png', 'door.png', 'door_FL.png', 'door_FR.png', 'door_RL.png', 'door_RR.png', 'fuel.png', 'high_watertemp.png', 'hood.png', 'lowfuel.png', 'trunk.png']
    .forEach(src => { const img = new Image(); img.src = src; });
  })();

  // 333ms Interval for background tasks
  setInterval(() => {
    $scope.$evalAsync(() => {
      if (latestData && latestData.electrics.lowfuel == 1) {
        $scope.data.warningCenterText = $sce.trustAsHtml('<span style="font-size: 25px;">Please refuel</span>');
      } else {
        $scope.data.speedVal = $sce.trustAsHtml(displayBuffer.speedVal + '<span class="unit2">' + displayBuffer.speedUnit + '</span>');
      }
      
      $scope.data.range = $sce.trustAsHtml(displayBuffer.rangeVal + '<span class="unit">' + displayBuffer.rangeUnit + '</span>');

      let now = Date.now();
      if (now - lastClockTick >= 1000) {
        secondsCounter++;
        lastClockTick = now;
        const d = new Date();
        $scope.data.date = String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear();
        if (latestData) $scope.data.time = latestData.customModules.environmentData.time;
      }
    });
  }, 333);

  $window.updateData = (data) => {
    latestData = data;
    $scope.$evalAsync(function () {
      const e = data.electrics, env = data.customModules.environmentData, eng = data.customModules.combustionEngineData;
      const now = Date.now();
      const isM  = units.uiUnitLength === "metric";
      const distFac = isM ? 0.001 : 0.0006215;      // metres -> km / miles
      const distUnit = isM ? "km" : "mi";
	  
      // --- Bootscreen check ---
      const ignition = e.ignitionLevel || 0;
      setBootscreen(ignition);
      if (bootscreenEnabled && ignition < 2) return;

	  //CLIMATE START

      const ctx = e.hvac_context || 0;
      const isFanActive = ctx === 1;
      const isSeat1Active = ctx === 2;
      const isSeat2Active = ctx === 3;
      const isAirflow1Active = ctx === 4;
      const isAirflow2Active = ctx === 5;

      let tempEnv = UiUnits.temperature(env.temperatureEnv);
      const tUnit = tempEnv.unit;

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
        }else if (airflowActive) {
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

      if (prevResetTrip !== null && e.resetTrip !== prevResetTrip) tripOffset = e.odometer || 0;
      prevResetTrip = e.resetTrip;

      // --- Door & Warning Logic ---
      let anyOpen = false;
      const accessItems = [
        ...["FL", "FR", "RL", "RR"].map(d => ({ key: `door_${d}_coupler_notAttached`, id: `door_${d}`, img: `door_${d}.png` })),
        { key: "hoodLatchCoupler_notAttached", id: "hood", img: "hood.png" }, { key: "trunkCoupler_notAttached", id: "trunk", img: "trunk.png" }
      ];

      accessItems.forEach(item => {
        const isOpen = e[item.key] === 1;
        const el = document.getElementById(item.id);
        if (el) el.style.backgroundImage = isOpen ? "url('" + item.img + "')" : "";
        if (isOpen) anyOpen = true;
      });

      if (els.doorMain) els.doorMain.style.backgroundImage = anyOpen ? "url('door.png')" : "";
      
      const mainShow = anyOpen ? "none" : "";
      els.line3.style.display = els.range.style.display = mainShow;
      
      if (anyOpen) {
        els.speedVal.style.display = "none";
        if (els.warningCenter) els.warningCenter.style.display = "none";
        els.fuelIcon.style.backgroundImage = els.warnBottom.style.backgroundImage = "";
      } else {
        const fuelLow = e.lowfuel == 1;
        els.speedVal.style.display = fuelLow ? "none" : "block";
        if (els.warningCenter) els.warningCenter.style.display = fuelLow ? "block" : "none";
      }

      // --- Speed & Menu Display ---
      const rawSpeed = Math.min(Math.max(UiUnits.speed(e.wheelspeed).val, 0), 999);
      displayBuffer.speedVal = rawSpeed.toFixed(0);
      displayBuffer.speedUnit = isM ? 'km/h' : 'mph';

      const tVal = Math.max((e.odometer || 0) - tripOffset, 0) * distFac;
      let avgConso = UiUnits.consumptionRate(eng.averageFuelConsumption * 1e-5);
      let curConso = UiUnits.consumptionRate(eng.currentFuelConsumption * 1e-5);
      const menuCfg = {
        1: { icon: 'fuel.png', unit: distUnit, val: eng.remainingRange * (isM ? 1 : 0.6215), dec: 0 },
        2: { icon: 'avg.png', unit: avgConso.unit, val: avgConso.val === "n/a" ? null : avgConso.val, dec: 1 },
        3: { icon: '', unit: curConso.unit, val: curConso.val === "n/a" ? null : curConso.val, dec: 1 },
        4: { icon: 'avg.png', unit: isM ? 'km/h' : 'mph', val: tVal / (secondsCounter / 3600 || 1), dec: 1 }
      };

      const ui = menuCfg[e.gaugesMenu];
      if (ui && !anyOpen) {
        els.fuelIcon.style.backgroundImage = ui.icon ? "url('" + ui.icon + "')" : "";
        displayBuffer.rangeVal = (typeof ui.val === "number" && isFinite(ui.val)) ? ui.val.toFixed(ui.dec) : "---";
        displayBuffer.rangeUnit = ui.unit;
      }

      if (e.gaugesMenu !== lastGaugesMenu) {
        lastGaugesMenu = e.gaugesMenu;
        $scope.data.range = $sce.trustAsHtml(displayBuffer.rangeVal + '<span class="unit">' + displayBuffer.rangeUnit + '</span>');
      }

      // --- Gear Handling ---
      const inMMode = typeof e.gear === 'string' && e.gear.includes('M');
      const inSMode = !inMMode && !['P','R','N','D'].includes(e.gear) && !e.manualShifterEnabled;
      const gearOff = inSMode ? 19 : 0;
      const gearTr = 'right 0.3s ease';

      if (inMMode) {
        // Hide PRNDS
        Object.values(els.gears).forEach(el => el.style.display = "none");
        els.gearText.style.display = 'none';
        els.gearNumDiv.style.display = 'none';
        $scope.data.gearNumber = "";

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
            box.style.cssText = 'position:absolute;bottom:225px;width:27px;height:35px;background-color:#ff0000;z-index:100;display:none;transition:' + gearTr + ';';
            gaugeDiv.appendChild(box);
            mGearBoxes.push(box);

            const txt = document.createElement('div');
            txt.style.cssText = 'position:absolute;bottom:230px;width:27px;height:25px;font-family:AudiType;font-size:25px;text-align:center;line-height:25px;z-index:101;color:white;transition:' + gearTr + ';';
            txt.textContent = i.toString();
            gaugeDiv.appendChild(txt);
            mGearTexts.push(txt);
          }
          mGearCount = maxGears;
        }

        // Position centered (highest gear left, 1 right)
        const mSpacing = 28;
        const stripW = (maxGears - 1) * mSpacing + 27;
        const margin = (180 - stripW) / 2;
        const startRight = 16 + Math.max(margin, 0);

        for (let i = 0; i < maxGears; i++) {
          const gearNum = i + 1;
          const boxRight = startRight + (gearNum - 1) * mSpacing;
          mGearBoxes[i].style.right = boxRight + 'px';
          mGearTexts[i].style.right = boxRight + 'px';
          mGearTexts[i].style.display = '';

          if (gearNum === currentGear) {
            mGearBoxes[i].style.display = 'block';
          } else {
            mGearBoxes[i].style.display = 'none';
          }
        }
      } else {
        // Hide manual gear elements
        mGearBoxes.forEach(el => { el.style.display = 'none'; });
        mGearTexts.forEach(el => { el.style.display = 'none'; });

        // Ensure transitions are active (bootscreen may have overridden CSS rule)
        els.gearText.style.transition = gearTr;
        els.gearNumDiv.style.transition = gearTr;
        Object.values(els.gears).forEach(el => { if (el) el.style.transition = gearTr; });

        // Show PRNDS, centered by default, shifted left in S mode
        els.gearText.style.display = '';
        els.gearNumDiv.style.display = '';
        els.gearText.style.right = (-39 + gearOff) + 'px';
        els.gearNumDiv.style.right = (1 + gearOff) + 'px';

        const boxR = { P: 149, R: 121, N: 93, D: 63, S: 35 };
        Object.keys(boxR).forEach(g => {
          if (els.gears[g]) {
            els.gears[g].style.right = (boxR[g] + gearOff) + 'px';
            els.gears[g].style.display = "none";
          }
        });

        if (!e.manualShifterEnabled) {
          $scope.data.gear = "P R N D S";
          const gearKey = ["P", "R", "N", "D"].includes(e.gear) ? e.gear : "S";
          if (els.gears[gearKey]) els.gears[gearKey].style.display = "block";

          $scope.data.gearNumber = "";
          if (gearKey === "S") {
            const match = String(e.gear).match(/\d+/);
            if (match) $scope.data.gearNumber = match[0];
          } else if (gearKey === "D") {
            const idx = e.gearIndex;
            if (idx && idx > 0) $scope.data.gearNumber = idx.toString();
          }
        }
      }

      // --- Trip & Odo ---
      $scope.data.trip = Math.min(tVal, 9999).toFixed(1);
      $scope.data.odo = Math.min((e.audi6_odo || 0) * distFac, 999999).toFixed(0);
      $scope.data.distanceUnit = distUnit;

      if (tempEnv.val.toFixed(1) > 99.9 || tempEnv.val.toFixed(1) < -99.9) {
        $scope.data.temp = "---" + tempEnv.unit;
      } else {
        $scope.data.temp = (tempEnv.val >= 0 ? "+" : "") + tempEnv.val.toFixed(1) + tempEnv.unit;
      }
      
      // --- Top Text ---
      els.toptext.style.cssText = "transform: scaleX(0.75); color: white;";
      let song = e.audi6_currentSongName || "";
      $scope.data.toptext = song.length > 18 ? song.substring(0, 15) + "..." : song;

      if (e.tcsoff == 1) {
        els.toptext.style.cssText = "transform: scaleX(1); color: #f99825;";
        $scope.data.toptext = "ESP OFF";
      }

      const warn = e.lowfuel == 1 ? 'lowfuel.png' : (e.high_watertemp == 1 ? 'high_watertemp.png' : null);
      if (warn) {
        els.line1.style.display = els.temp.style.display = "none";
        els.warning.style.backgroundImage = "url('" + warn + "')";
        $scope.data.toptext = "";
      } else {
        els.line1.style.display = els.temp.style.display = "";
        els.warning.style.backgroundImage = "";
      }
    });
  };
});