angular.module('gaugesScreen', [])
  .controller('GaugesScreenController', function($scope, $window, $sce, $timeout) {

    const units = {
      uiUnitConsumptionRate: "metric",
      uiUnitDate: "ger",
      uiUnitEnergy: "metric",
      uiUnitLength: "metric",
      uiUnitPower: "hp",
      uiUnitPressure: "bar",
      uiUnitTemperature: "c",
      uiUnitTorque: "metric",
      uiUnitVolume: "l",
      uiUnitWeight: "kg"
    };

    $scope.display = {};
    $scope.state = { showTime: true };

    let MENU_ITEMS = {};
    let lastMenuItemsJson = '';

    const D = (section, key, fallback = '') =>
      (MENU_ITEMS[section] && MENU_ITEMS[section][key]) || fallback;

    let previousSongIndex = 0;
    let lastBootscreenState = null;

    const setBootscreen = (ignition) => {
      const bootscreen = document.getElementById('bootscreen');
      const interfaceRoot = document.querySelector('.interface-root');
      if (!bootscreen || !interfaceRoot) return;

      const shouldShow = ignition < 2;

      if (shouldShow !== lastBootscreenState) {
        if (shouldShow) {
          bootscreen.classList.remove('fadeout');
          bootscreen.classList.add('fadein');
        } else {
          bootscreen.classList.remove('fadein');
          bootscreen.classList.add('fadeout');
        }

        Array.from(interfaceRoot.children).forEach((child) => {
          if (child.id === 'bootscreen' || child.classList.contains('time-display')) return;
          if (shouldShow) {
            child.style.opacity = '0';
            child.style.visibility = 'hidden';
            child.style.transition = 'opacity 0.5s ease-in-out';
          } else {
            setTimeout(() => {
              child.style.visibility = 'visible';
              child.style.opacity = '1';
            }, 400);
          }
        });

        lastBootscreenState = shouldShow;
      }
    };

    $window.setup = (setupData) => {
      for (const dk in setupData) {
        if (typeof dk === "string" && dk.startsWith("uiUnit")) {
          units[dk] = setupData[dk];
        }
      }
      vueEventBus.emit('SettingsChanged', {values: units});
    };

    const getProximityLevel = (dist, isOuter) => {
      if (isOuter) return dist < 0.4 ? 'level3' : (dist < 0.9 ? 'level2' : (dist < 1.5 ? 'level1' : 'off'));
      const steps = [0.25, 0.4, 0.55, 0.75, 1.0, 1.25, 1.5];
      const idx = steps.findIndex(s => dist < s);
      return idx !== -1 ? `level${7 - idx}` : 'off';
    };

    const processBumper = (hits, offset, isActive) => {
      if (!isActive || !hits || !hits.length) {
        for (let i = 0; i < 4; i++) $scope.display['proximity' + (i + 1 + offset)] = 'off';
        return;
      }
      const size = Math.ceil(hits.length / 4);
      for (let i = 0; i < 4; i++) {
        const slice = hits.slice(i * size, (i + 1) * size);
        const dist = slice.length ? Math.min(...slice) : 100;
        $scope.display['proximity' + (i + 1 + offset)] = getProximityLevel(dist, i === 0 || i === 3);
      }
    };

    const clearParking = () => {
      for (let i = 1; i <= 8; i++) $scope.display['proximity' + i] = 'off';
      $scope.display.isParkingVisible = false;
    };

    $window.updateData = (data) => {
      $scope.$evalAsync(() => {
        const e = data.electrics;

        if (e.mmi_menu_items && e.mmi_menu_items !== lastMenuItemsJson) {
          try {
            MENU_ITEMS = JSON.parse(e.mmi_menu_items);
            lastMenuItemsJson = e.mmi_menu_items;
          } catch (_) {
            lastMenuItemsJson = '';
          }
        }

        const ignition = e.ignitionLevel || 0;
        const timeEl = document.querySelector('.time-display');
        const volumeIconEl = document.getElementById('volume_icon');
        const centerTextEl = document.querySelector('.center-text');

        setBootscreen(ignition);

        if (ignition < 2) {
          $scope.state.showTime = true;
          $scope.display.timestamp = new Date();
          return;
        }

        function setCenterText(text) {
          if (!centerTextEl) return;
          centerTextEl.style.animation = 'none';
          centerTextEl.style.transform = 'translateX(0)';
          centerTextEl.style.display = 'block';
          centerTextEl.style.overflow = 'hidden';
          centerTextEl.style.whiteSpace = 'nowrap';
          centerTextEl.style.textOverflow = 'ellipsis';
          centerTextEl.style.maxWidth = '100%';
          centerTextEl.textContent = text;
        }

		// CASE 1: PARKING
		const frontHits = Object.values(e.parkingSensorHits?.frontBumper || {});
		const isCloseFront = frontHits.some(d => d < 1.5);
		const autoShowFront = e.frontParkingSensorsEnabled === 1 && isCloseFront;

		if (((e.reverse === 1 && e.rearParkingSensorsEnabled === 1) || autoShowFront) && e.button_parkingsensors === 1) {
          centerTextEl.style.display = 'none';
          $scope.state.showTime = false;
          if (timeEl) timeEl.textContent = D('SIMPLE', 'parkingWarning', 'Look! Safe to move?');
          $scope.display.text_0 = D('SIMPLE', 'parkingTitle', 'Audi parking system');          
          $scope.display.text_1 = '';                              
          $scope.display.text_2 = '';                              
          $scope.display.text_3 = D('SIMPLE', 'parkingSet', 'Set');                    
          $scope.display.text_4 = '';
          document.body.style.backgroundImage = e.frontParkingSensorsEnabled === 1 ? "url('parking_system_front.png')" : "url('parking_system.png')";
          if (volumeIconEl) volumeIconEl.style.display = 'none';

          $scope.display.isParkingVisible = true;

          // Rear bumper sensors (proximity 1-4)
          processBumper(e.parkingSensorHits?.rearBumper, 0, true);

		  // Front bumper sensors (proximity 5-8)
          if (e.frontParkingSensorsEnabled && e.parkingSensorHits?.frontBumper) {
            const hits = Object.values(e.parkingSensorHits.frontBumper);
            const size = Math.ceil(hits.length / 4);
            for (let i = 0; i < 4; i++) {
              const slice = hits.slice(i * size, (i + 1) * size);
              const dist = slice.length ? Math.min(...slice) : 100;
              const isOuter = (i === 0 || i === 3);
              
              if (isOuter) {
                $scope.display['proximity' + (i + 5)] = getProximityLevel(dist, true);
              } else {
                // Custom 4-level logic for front inner sensors
                // Maps 1.5m range into levels 1-4 instead of 1-7
                const steps = [0.4, 0.7, 1.1, 1.5];
                const idx = steps.findIndex(s => dist < s);
                $scope.display['proximity' + (i + 5)] = idx !== -1 ? `level${7 - idx}` : 'off';
              }
            }
          }

          return;
        }

        // Not parking — clear sensor state
        clearParking();

		// ── CASE 2: MEDIA
		centerTextEl.style.display = 'block';
		$scope.state.showTime = true;
		document.body.style.backgroundImage = '';
		if (timeEl) {
		  const now = new Date();
		  const hh = String(now.getHours()).padStart(2, '0');
		  const mm = String(now.getMinutes()).padStart(2, '0');
		  timeEl.textContent = hh + ':' + mm;
		}
		if (volumeIconEl) volumeIconEl.style.display = 'block';
		$scope.display.text_0 = D('SIMPLE', 'mediaTitle', 'CD 1');
        $scope.display.text_1 = D('SIMPLE', 'mediaCorner1', 'Changer');
        $scope.display.text_2 = '';
        $scope.display.text_3 = D('SIMPLE', 'mediaCorner3', 'CD control');
        $scope.display.text_4 = D('SIMPLE', 'mediaCorner4', 'Sound');

        const songNames = (data.customModules?.audi6_songs?.names) || [];
        const currentIndex = e.current_music_index || 1;
        const currentSong = songNames[currentIndex - 1] || D('SIMPLE', 'unknownSong', 'Unknown');
        const volume = e.audi6_volume || 0;

        if (volumeIconEl) {
          volumeIconEl.style.backgroundSize = '100% 100%';
          volumeIconEl.style.backgroundPosition = 'center';
          volumeIconEl.style.backgroundImage =
            volume === 0  ? "url('mute-icon.png')"      :
            volume <= 2.5 ? "url('low-volume-icon.png')" :
                            "url('high-volume-icon.png')";
          volumeIconEl.style.display = 'block';
        }

        if (previousSongIndex !== currentIndex) {
          setCenterText(currentSong);
        }
        previousSongIndex = currentIndex;
      });
    };

    (function init() {
      const clock = () => {
        if ($scope.state.showTime) {
          $scope.display.timestamp = new Date();
        } else {
          $scope.display.timestamp = '';
        }
        $timeout(clock, 1000);
      };
      clock();
      $window.preloads = [
        "bootscreen.png", "ui.png",
        "parking_system.png", "parking_system_front.png",
        "rear_1_1.png", "rear_1_2.png", "rear_1_3.png",
        "rear_2_1.png", "rear_2_2.png", "rear_2_3.png", "rear_2_4.png", "rear_2_5.png", "rear_2_6.png", "rear_2_7.png",
        "high-volume-icon.png", "low-volume-icon.png", "mute-icon.png"
      ].map(s => { const i = new Image(); i.src = s; return i; });
    })();
  });