angular.module('gaugesScreen', [])
  .controller('GaugesScreenController', function($scope, $window, $sce, $timeout) {

    const MENU = {
      NAV: 1, MEDIA: 2, CLIMATE: 4, CAR: 5, NAME: 6, TEL: 7,
      PARKING_GRAPHIC: 100, REVERSE_CAMERA: 101
    };

    const fade = (hex, p = 0.4) => {
      const f = parseInt(hex.slice(1), 16);
      const [R, G, B] = [f >> 16, (f >> 8) & 0xFF, f & 0xFF];
      return '#' + (0x1000000 +
        (Math.round((255 - R) * p) + R) * 0x10000 +
        (Math.round((255 - G) * p) + G) * 0x100 +
        (Math.round((255 - B) * p) + B)
      ).toString(16).slice(1);
    };

    const PALETTE = {
      BLUE:   { main: '#007eff', alt: fade('#007eff'), iconSet: 'blue'   },
      GREEN:  { main: '#008000', alt: fade('#008000'), iconSet: 'green'  },
      ORANGE: { main: '#ff1400', alt: fade('#ff1400'), iconSet: 'orange' },
      YELLOW: { main: '#ffbd00', alt: fade('#ffbd00'), iconSet: 'none' },
      RED:    { main: '#ff0000', alt: fade('#ff0000'), iconSet: 'red'    },
      NONE:   { main: '',        alt: '',              iconSet: 'none'   }
    };

    const ASSETS = {
      blue:   { mute: 'mute-blue-icon.png',   low: 'low-volume-blue-icon.png',   high: 'high-volume-blue-icon.png'   },
      green:  { mute: 'mute-green-icon.png',  low: 'low-volume-green-icon.png',  high: 'high-volume-green-icon.png'  },
      orange: { mute: 'mute-orange-icon.png', low: 'low-volume-orange-icon.png', high: 'high-volume-orange-icon.png' },
      red:    { mute: 'mute-icon.png',        low: 'low-volume-icon.png',        high: 'high-volume-icon.png'        },
      none:   { mute: '',                     low: '',                           high: ''                            }
    };

    const SEL = {
      title:    '.title-text',
      cornerTL: '.corner-tl', cornerTR: '.corner-tr',
      cornerBL: '.corner-bl', cornerBR: '.corner-br',
      parking:  '.parking-overlay',
      volume:   '#volume-level',
      sBL: '#selector-bl', sTL: '#selector-tl',
      sBR: '#selector-br', sTR: '#selector-tr',
      overlay:  '#visual-overlay',
      status1:  '#sub-indicators',  status2: '#sub-indicators2',
      status3:  '#sub-indicators3', status4: '#sub-indicators4',
      scrollOverlay: '#scroll-overlay'
    };

    // submenu index → corner selector element + mirror transform
    const SUBMENU_SEL = {
      1: { el: SEL.sTL, tf: 'none'                    },
      2: { el: SEL.sTR, tf: 'scaleX(-1)'              },
      3: { el: SEL.sBL, tf: 'scaleY(-1)'              },
      4: { el: SEL.sBR, tf: 'scaleX(-1) scaleY(-1)'  }
    };

    // submenu index → active corner label element
    const SUBMENU_CORNER = {
      1: SEL.cornerTL, 2: SEL.cornerTR, 3: SEL.cornerBL, 4: SEL.cornerBR
    };

    // Populated from electrics.mmi_menu_items (defined in mmi.lua) — edit labels there
    let MENU_ITEMS = {};
	let lastMenuItemsJson = '';
	let units = { uiUnitPressure: 'bar' };

    const T = (text) => (MENU_ITEMS.LABELS && MENU_ITEMS.LABELS[text]) || text;
    const D = (section, key, fallback = '') =>
      (MENU_ITEMS[section] && MENU_ITEMS[section][key]) || fallback;

    $scope.display = {};
    $scope.state   = { showTime: true };

    const find        = (s) => document.querySelector(s);
    const updateStyle = (s, props) => {
      const el = find(s);
      if (!el) return;
      for (const [k, v] of Object.entries(props)) {
        if (el.style[k] !== v) el.style[k] = v;
      }
    };

    const getProximityLevel = (dist, levels) => {
      const steps = {
        3: [0.40, 0.90, 1.50],
        4: [0.25, 0.55, 0.95, 1.40],
        5: [0.20, 0.40, 0.65, 0.95, 1.30],
        7: [0.25, 0.40, 0.55, 0.75, 1.00, 1.25, 1.50]
      }[levels] || [0.25, 0.40, 0.55, 0.75, 1.00, 1.25, 1.50];
      const idx = steps.findIndex(s => dist < s);
      return idx !== -1 ? `level${levels - idx}` : 'off';
    };

    // Apply palette to title/corners; optionally highlight one corner at full saturation.
    const applyTheme = (theme, activeCorner = null) => {
      updateStyle(SEL.title, { color: theme.main });
      [SEL.cornerTL, SEL.cornerTR, SEL.cornerBL, SEL.cornerBR]
        .forEach(s => updateStyle(s, { color: s === activeCorner ? theme.main : theme.alt }));

      if (!$scope.state.showTime) {
        updateStyle(SEL.volume, { backgroundImage: 'none', display: 'none' });
        return;
      }
      const vol = $scope.cachedElectrics?.audi6_volume || 0;
      const set = ASSETS[theme.iconSet] || ASSETS.red;
      const src = vol === 0 ? set.mute : vol <= 2.5 ? set.low : set.high;
      updateStyle(SEL.volume, { backgroundImage: src ? `url('${src}')` : 'none', display: src ? 'block' : 'none' });
    };

    // Show the corner-selector graphic for a given submenu index.
    const activateSubmenuSelector = (sub, imgUrl) => {
      const cfg = SUBMENU_SEL[sub];
      if (cfg) updateStyle(cfg.el, { backgroundImage: `url('${imgUrl}')`, display: 'block', transform: cfg.tf });
    };

	const clearInterface = () => {
	  ['mainLabel','bottomMainLabel','title',
	   'cornerTL','cornerTR','cornerBL','cornerBR',
	   'menuItem1','menuItem2','menuItem3','menuItem4','menuItem5','menuItem6',
	   'menuValue1','menuValue2','menuValue3','menuValue4','menuValue5','menuValue6',
	   'proximity1','proximity2','proximity3','proximity4',
	   'proximity5','proximity6','proximity7','proximity8',
	   'leftValue','rightValue','leftSubValue','rightSubValue'
	  ].forEach(f => $scope.display[f] = f.startsWith('proximity') ? 'off' : '');

	  $scope.display.isParkingVisible = false;
	  $scope.display.isCarBatteryMenu = false;
	  $scope.display.batterySegments  = 0;

	  updateStyle('.center-label',        { color: '', transform: 'none', textAlign: '', left: '' });
	  updateStyle('.bottom-center-label', { color: '', transform: 'none' });

	  [SEL.sTL, SEL.sBL, SEL.sTR, SEL.sBR,
	   SEL.overlay, SEL.status1, SEL.status2, SEL.status3, SEL.status4,
	   SEL.parking, SEL.volume, SEL.scrollOverlay
	  ].forEach(s => updateStyle(s, { backgroundImage: 'none', display: 'none', transform: 'none' }));

	  for (let i = 1; i <= 6; i++) {
		updateStyle(`.menu-item-${i}`, { display: 'none', color: '', transform: 'none', left: '', right: '', width: '', textAlign: '' });
		updateStyle(`.value-box-${i}`, { display: 'none', transform: 'none', padding: '', right: '', fontSize: '' });
	  }

	  updateStyle('.value-indicator-2',   { display: 'none', transform: 'none' });
	  updateStyle('.value-indicator-3',   { display: 'none', transform: 'none' });
	  updateStyle('.value-indicator-4',   { display: 'none', transform: 'none' });
	  updateStyle('.value-indicator-5',   { display: 'none', transform: 'none' });
	  updateStyle('.value-indicator-6',   { display: 'none', transform: 'none' });

	  ['.value-indicator-2','.value-indicator-3','.value-indicator-4','.value-indicator-5','.value-indicator-6'].forEach(s => {
		const el = find(s);
		if (el) { el.classList.remove('indicator-selected'); el.style.bottom = ''; el.style.borderColor = ''; el.style.removeProperty('--indicator-color'); }
	  });
	  updateStyle('#front-sensors-group', { transform: 'none' });

	  const circ = find('.value-indicator-4');
	  if (circ) circ.classList.remove('tel-active', 'climate-active', 'sideassist-active', 'suspension-active', 'fanheated-active', 'center-vent-selected', 'ext-lighting-indicator', 'active');

	  const dial = find('#circle-dial');
	  if (dial) {
		  dial.style.display = 'none';
		  dial.style.bottom = '38px';
	  }
	  ['up', 'down'].forEach(dir => {
		const el = find(`#scroll-indicator-${dir}`);
		if (el) el.style.display = 'none';
	  });
	};

    let lastBootscreenState = null;
    const setBootscreen = (ignition) => {
      const bootscreen    = document.getElementById('bootscreen');
      const interfaceRoot = document.querySelector('.interface-root');
      if (!bootscreen || !interfaceRoot) return;

      const shouldShow = ignition < 2;
      if (shouldShow === lastBootscreenState) return;

      bootscreen.classList.toggle('fadein',  shouldShow);
      bootscreen.classList.toggle('fadeout',  !shouldShow);

      Array.from(interfaceRoot.children).forEach(child => {
        if (child.id === 'bootscreen' || child.classList.contains('time-display')) return;
        if (shouldShow) {
          Object.assign(child.style, { opacity: '0', visibility: 'hidden', transition: 'opacity 0.5s ease-in-out' });
        } else {
          setTimeout(() => Object.assign(child.style, { visibility: 'visible', opacity: '1' }), 400);
        }
      });

      lastBootscreenState = shouldShow;
    };

    const SCROLL_ARC = {
      1: { left: 67, bottom: 193 }, 2: { left: 57, bottom: 165 },
      3: { left: 52, bottom: 137 }, 4: { left: 52, bottom: 109 },
      5: { left: 57, bottom:  81 }, 6: { left: 67, bottom:  53 }
    };

    // Line width per scroll index — set once, used everywhere
    const SCROLL_LINE_WIDTHS = { 1: 15, 2: 25, 3: 30, 4: 30, 5: 25, 6: 15 };

    const setScrollOverlay = (scroll, color, { startSlot = 1, maxSlots = 6, leftOffset = 0 } = {}) => {
      const el = find(SEL.scrollOverlay);
      if (!el) return;
      el.style.display = 'block';
      const slots     = maxSlots - startSlot + 1;
      const slotIndex = ((scroll - 1) % slots) + startSlot;
      const pos       = SCROLL_ARC[slotIndex] || SCROLL_ARC[1];
      el.style.setProperty('--row-bottom',   pos.bottom + 'px');
      el.style.setProperty('--scroll-left',  (pos.left + leftOffset) + 'px');
      el.style.setProperty('--scroll-color', color);
      el.style.setProperty('--scroll-line-width', (SCROLL_LINE_WIDTHS[slotIndex] || 20) + 'px');
    };

    const setMenuItems = (items, scroll, color, { startSlot = 1, maxSlots = 6 } = {}) => {
      if (!items?.length) return;
      const slots       = maxSlots - startSlot + 1;
      const sel         = Math.max(1, scroll || 1) - 1;
      const windowStart = items.length > slots ? Math.floor(sel / slots) * slots : 0;

      for (let slot = startSlot; slot <= maxSlots; slot++) {
        const idx = windowStart + (slot - startSlot);
        if (idx < items.length) {
          $scope.display[`menuItem${slot}`] = items[idx];
          updateStyle(`.menu-item-${slot}`, { display: 'block', color: idx === sel ? 'white' : color });
        } else {
          updateStyle(`.menu-item-${slot}`, { display: 'none' });
        }
      }

      const offset  = (startSlot - 1) * 30;
      const hasUp   = windowStart > 0;
      const hasDown = windowStart + slots < items.length;
      ['up', 'down'].forEach(dir => {
        const el   = find(`#scroll-indicator-${dir}`);
        const show = dir === 'up' ? hasUp : hasDown;
        el.textContent     = dir === 'up' ? '▲' : '▼';
        el.style.display   = show ? 'block' : 'none';
        el.style.color     = color;
        el.style.transform = '';
        if (dir === 'up') el.style.setProperty('--scroll-offset', offset + 'px');
      });
    };

    const HANDLERS = {
      [MENU.NAV]: (e) => {
        Object.assign($scope.display, { cornerBL: T('Nav-Info'), cornerBR: T('Destination') });
        updateStyle('body', { backgroundImage: "url('hud.png')" });
        applyTheme(PALETTE.BLUE, null);
      },

      [MENU.MEDIA]: (e, d) => {
        const activeSub = e.mmi_activeSubmenu || 0;
        Object.assign($scope.display, {
          title: e.mmi_changerTitle, cornerTL: T('Changer'), cornerTR: T('Source'),
          cornerBL: T('CD control'), cornerBR: T('Sound')
        });
        applyTheme(PALETTE.ORANGE, SUBMENU_CORNER[activeSub] || null);

        if (activeSub >= 1 && activeSub <= 4) {
          const subLists   = [null, MENU_ITEMS.MEDIA_CHANGER, MENU_ITEMS.MEDIA_SOURCE, MENU_ITEMS.MEDIA_CONTROL, MENU_ITEMS.MEDIA_SOUND];
          const subMaxSlot = [null, 6, 5, 6, 6];
          updateStyle('body', { backgroundImage: "url('orange_ui.png')" });
          activateSubmenuSelector(activeSub, 'select_orange2.png');

          const soundDv = e.mmi_detailView || 0;
          if (activeSub === 4 && soundDv >= 20 && soundDv <= 23) {
            // Sound dial view (Balance/Fader/Treble/Bass)
            const dialLabels = { 20: T('Balance'), 21: T('Fader'), 22: T('Treble'), 23: T('Bass') };
            $scope.display.mainLabel = dialLabels[soundDv];
            const level = e.mmiscroll || 1;
            const maxVal = 19;
            const circ = find('.value-indicator-4');
            const dial = find('#circle-dial');
            if (circ) {
              updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
              circ.classList.add('sideassist-active');
			  circ.style.setProperty('--indicator-color', PALETTE.ORANGE.main);
              circ.textContent = '';
              if (dial) {
                dial.style.display = 'block';
                dial.style.bottom = '11px';
                const cx = 90, cy = 90, r = 80;
                let lowLabel, highLabel;
                if (soundDv === 20) { lowLabel = T('left'); highLabel = T('right'); }
                else if (soundDv === 21) { lowLabel = T('rear'); highLabel = T('front'); }
                else { lowLabel = '-'; highLabel = '+'; }
                dial.innerHTML = Array.from({ length: maxVal }, (_, i) => {
                  const val = i + 1;
                  const angle = (i / (maxVal - 1)) * 270 - 225;
                  const rad = angle * Math.PI / 180;
                  const x = cx + r * Math.cos(rad);
                  const y = cy + r * Math.sin(rad);
                  const color = val === level ? 'white' : PALETTE.ORANGE.main;
                  if (val === 1) {
                    return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
                      font-size="13" font-weight="bold" font-family="inherit" fill="${color}">${lowLabel}</text>`;
                  } else if (val === maxVal) {
                    return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
                      font-size="13" font-weight="bold" font-family="inherit" fill="${color}">${highLabel}</text>`;
                  } else if (val === 10) {
                    return `<circle cx="${x}" cy="${y}" r="5" fill="${color}" />`;
                  } else {
                    return `<circle cx="${x}" cy="${y}" r="3" fill="${color}" />`;
                  }
                }).join('');
              }
            }
            updateStyle('body', { backgroundImage: "url('orange_line_ui.png')" });
          } else if (activeSub === 4 && soundDv === 24) {
            // DSP BOSE settings
            $scope.display.mainLabel = T('DSP BOSE');
            setMenuItems(MENU_ITEMS.DSP_BOSE || [], e.mmiscroll, PALETTE.ORANGE.main, { startSlot: 2 });
            setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { startSlot: 2 });
            const focusMode = e.mmi_soundFocusMode || 0;
            const pilotOn = e.mmi_audioPilot || 0;
            $scope.display.menuValue2 = focusMode === 1 ? T('rear') : T('Driver');
            $scope.display.menuValue3 = pilotOn ? T('on') : T('off');
            updateStyle('.value-box-2', { display: 'inline-flex', backgroundColor: e.mmiscroll === 1 ? 'white' : PALETTE.ORANGE.main, color: 'black', transform: 'none' });
            updateStyle('.value-box-3', { display: 'inline-flex', backgroundColor: e.mmiscroll === 2 ? 'white' : PALETTE.ORANGE.main, color: 'black', transform: 'none' });
            updateStyle('body', { backgroundImage: "url('orange_line_ui.png')" });
          } else if (activeSub === 4 && soundDv === 25) {
            // Volume settings list with circle indicators
            $scope.display.mainLabel = T('Volume settings');
            setMenuItems(MENU_ITEMS.VOLUME_SETTINGS || [], e.mmiscroll, PALETTE.ORANGE.main, { startSlot: 2 });
            setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { startSlot: 2 });
            const volIndicators = [
              { sel: '.value-indicator-2', scroll: 1 },
              { sel: '.value-indicator-3', scroll: 2 },
              { sel: '.value-indicator-4', scroll: 3 },
              { sel: '.value-indicator-5', scroll: 4 },
              { sel: '.value-indicator-6', scroll: 5 }
            ];
            volIndicators.forEach(({ sel, scroll }) => {
              updateStyle(sel, { display: 'flex', transform: 'none' });
              const el = find(sel);
              if (el) {
                el.classList.toggle('indicator-selected', e.mmiscroll === scroll);
                el.style.setProperty('--indicator-color', PALETTE.ORANGE.main);
              }
            });
            updateStyle('body', { backgroundImage: "url('orange_line_ui.png')" });
          } else if (activeSub === 4 && soundDv >= 26 && soundDv <= 30) {
            // Volume dial (5 levels, - to +)
            const volDialLabels = { 26: T('Traffic report'), 27: T('Voice guidance'), 28: T('Audio during route guid.'), 29: T('Speech dialogue system'), 30: T('Telephone volume') };
            $scope.display.mainLabel = volDialLabels[soundDv];
            const level = e.mmiscroll || 1;
            const maxVal = 5;
            const circ = find('.value-indicator-4');
            const dial = find('#circle-dial');
            if (circ) {
              updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
              circ.classList.add('sideassist-active');
              circ.style.setProperty('--indicator-color', PALETTE.ORANGE.main);
              circ.textContent = '';
              if (dial) {
                dial.style.display = 'block';
                dial.style.bottom = '11px';
                const cx = 90, cy = 90, r = 80;
                dial.innerHTML = Array.from({ length: maxVal }, (_, i) => {
                  const val = i + 1;
                  const angle = (i / (maxVal - 1)) * 270 - 225;
                  const rad = angle * Math.PI / 180;
                  const x = cx + r * Math.cos(rad);
                  const y = cy + r * Math.sin(rad);
                  const color = val === level ? 'white' : PALETTE.ORANGE.main;
                  if (val === 1) {
                    return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
                      font-size="16" font-weight="bold" font-family="inherit" fill="${color}">-</text>`;
                  } else if (val === maxVal) {
                    return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
                      font-size="16" font-weight="bold" font-family="inherit" fill="${color}">+</text>`;
                  } else if (val === 3) {
                    return `<circle cx="${x}" cy="${y}" r="5" fill="${color}" />`;
                  } else {
                    return `<circle cx="${x}" cy="${y}" r="3" fill="${color}" />`;
                  }
                }).join('');
              }
            }
            updateStyle('body', { backgroundImage: "url('orange_line_ui.png')" });
          } else if (activeSub === 4) {
            // Sound list with circle indicators
            setMenuItems(subLists[4], e.mmiscroll, PALETTE.ORANGE.main, { maxSlots: 6 });
            setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { maxSlots: 6 });
            const soundIndicators = [
              { sel: '.value-indicator-2', scroll: 1, bottom: '188px' },
              { sel: '.value-indicator-3', scroll: 2, bottom: '160px' },
              { sel: '.value-indicator-5', scroll: 3, bottom: '132px' },
              { sel: '.value-indicator-6', scroll: 4, bottom: '104px' }
            ];
            soundIndicators.forEach(({ sel, scroll, bottom }) => {
              updateStyle(sel, { display: 'flex', transform: 'none', bottom: bottom, borderColor: 'white' });
              const el = find(sel);
              if (el) {
                el.classList.toggle('indicator-selected', e.mmiscroll === scroll);
                el.style.setProperty('--indicator-color', PALETTE.ORANGE.main);
              }
            });
            // Right-pointing arrows on DSP BOSE and Volume settings
            const soundList = subLists[4] || [];
            for (let i = 5; i <= soundList.length; i++) {
              updateStyle(`.menu-item-${i}`, { right: '130px' });
              $scope.display[`menuValue${i}`] = 'ᐅ';
              updateStyle(`.value-box-${i}`, {
                display: 'inline-flex', backgroundColor: 'transparent',
                color: e.mmiscroll === i ? 'white' : PALETTE.ORANGE.main,
                padding: '0', right: '100px', transform: 'none', fontSize: '22px'
              });
            }
          } else {
            setMenuItems(subLists[activeSub], e.mmiscroll, PALETTE.ORANGE.main, { maxSlots: subMaxSlot[activeSub] });
            setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { maxSlots: subMaxSlot[activeSub] });
          }
        } else {
          Object.assign($scope.display, { mainLabel: e.mmi_sourceLabel });
          updateStyle('body', { backgroundImage: "url('orange_line_ui.png')" });
          const songs    = d.customModules?.audi6_songs?.names || [];
          const numbered = songs.map((n, i) => `${String(i + 1).padStart(2, '0')} - ${n}`);
          setMenuItems(numbered, e.mmiscroll || e.current_music_index || 1, PALETTE.ORANGE.main, { startSlot: 2 });
          setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { startSlot: 2 });
        }
      },

      [MENU.CLIMATE]: (e) => {
        const ctx      = e.hvac_context || 0;
        const isPass   = ctx === 3 || ctx === 5;
        const isAir    = ctx === 4 || ctx === 5;
        const isHeat   = ctx === 2 || ctx === 3;
        const isActive = ctx !== 0;

        const airflow1   = e.button_airflow1 || 0;
        const airflow2   = e.button_airflow2 || 0;
        const airflowVal = isPass ? airflow2 : airflow1;

        $scope.display.leftValue     = isPass ? (e.button_fan || 0)         : (e.button_heatedseat1 || 0);
        $scope.display.rightValue    = isPass ? (e.button_heatedseat2 || 0) : (e.button_fan || 0);
        $scope.display.leftSubValue  = isPass ? '' : airflow1 === 0 ? T('auto') : '';
        $scope.display.rightSubValue = isPass ? (airflow2 === 0 ? T('auto') : '') : '';

        const items = MENU_ITEMS.CLIMATE || [];
        Object.assign($scope.display, {
          title:    isActive ? (isPass ? T('Passenger') : T('Driver')) : T('Setup AC'),
          cornerTL: isPass ? T('Seat heat.')    : T('Blower'),
          cornerTR: isPass ? T('Blower')        : T('Seat heat.'),
          cornerBL: isPass ? ''              : T('Distribution'),
          cornerBR: isPass ? T('Distribution')  : '',
          menuItem1: items[0], menuItem2: items[1], menuItem3: items[2],
          menuItem4: isAir ? T('auto') : items[3],
          menuItem5: items[4],  menuItem6: items[5],
          menuValue1: e.button_econ          >  0 ? T('on') : T('off'),
          menuValue2: e.button_recirculation == 1 ? T('on') : T('off'),
          menuValue3: e.mmi_synchron == 1 ? T('on') : T('off'), menuValue5: items.length > 4 ? ((e.mmi_auxHeatingActive ?? 0) == 1 ? T('on') : T('off')) : '',menuValue6: items.length > 5 ? ((e.mmi_auxVentActive ?? 0) == 1 ? T('on') : T('off')) : ''
        });

        // ctx → active corner (ctx 1 depends on isPass)
        const ctxCorner = { 2: SEL.cornerTR, 3: SEL.cornerTL, 4: SEL.cornerBL, 5: SEL.cornerBR };
        applyTheme(PALETTE.ORANGE, ctxCorner[ctx] || (ctx === 1 ? (isPass ? SEL.cornerTR : SEL.cornerTL) : null));

        updateStyle(SEL.status1, { display: 'block', backgroundImage: "url('fan_and_heatedseats.png')", transform: isPass ? 'scaleX(-1)' : 'none' });

        // airflow / heat / fan sub-indicators
        const showArrows = airflowVal >= 1 && airflowVal <= 7;
        updateStyle(SEL.status4, {
          display:         showArrows ? 'block' : 'none',
          backgroundImage: `url('airflow${airflowVal}.png')`,
          transform:       isPass ? 'scaleX(-1)' : 'none'
        });
        if (isAir) {
          updateStyle(SEL.overlay,  { display: 'block', backgroundImage: "url('airflow.png')" });
          updateStyle(SEL.status3, { display: showArrows ? 'block' : 'none', backgroundImage: `url('airflow${airflowVal}_2.png')`, transform: 'none' });
        } else if (isHeat) {
          updateStyle(SEL.status2, { display: 'block', backgroundImage: "url('heatedseats_overlay.png')", transform: isPass ? 'scaleX(-1)' : 'none' });
          updateStyle(SEL.status3, { display: 'none' });
        } else {
          updateStyle(SEL.status2, { display: ctx === 1 ? 'block' : 'none', backgroundImage: "url('fan_overlay.png')", transform: 'none' });
          updateStyle(SEL.status3, { display: 'none' });
        }

        // corner selector highlights
        updateStyle(SEL.sTL, { display: (ctx === 1 && !isPass) || ctx === 3 ? 'block' : 'none', backgroundImage: "url('select_orange.png')", transform: 'none' });
        updateStyle(SEL.sTR, { display: (ctx === 1 &&  isPass) || ctx === 2 ? 'block' : 'none', backgroundImage: "url('select_orange.png')", transform: 'scaleX(-1)' });
        updateStyle(SEL.sBL, { display: ctx === 4 ? 'block' : 'none', backgroundImage: "url('select_orange.png')", transform: 'scaleY(-1)' });
        updateStyle(SEL.sBR, { display: ctx === 5 ? 'block' : 'none', backgroundImage: "url('select_orange.png')", transform: 'scaleX(-1) scaleY(-1)' });

        // circular dial
        const circ = find('.value-indicator-4');
        const dial = find('#circle-dial');
        if (circ && isActive) {
          updateStyle('.value-indicator-4', { display: 'flex', transform: isAir ? 'none' : 'scale(1.3)' });
          circ.classList.remove('suspension-active');
          if (isAir) {
            circ.classList.add('climate-active');
            circ.classList.remove('fanheated-active');
            circ.textContent = '';
            if (dial) dial.style.display = 'none';
          } else {
            circ.classList.remove('climate-active');
            circ.classList.add('fanheated-active');
            const currentVal = isHeat
              ? (isPass ? (e.button_heatedseat2 || 0) : (e.button_heatedseat1 || 0))
              : (e.button_fan || 0);
            const maxVal = isHeat ? 6 : 12;
            if (dial) {
              dial.style.display = 'block';
              const cx = 90, cy = 90, r = 80;
              const minVal = isHeat ? 0 : 1;
              const count = maxVal - minVal + 1;
              dial.innerHTML = Array.from({ length: count }, (_, idx) => {
                const i = idx + minVal;
                const angle = (idx / (count - 1)) * 270 - 225;
                const rad   = angle * Math.PI / 180;
                return `<text x="${cx + r * Math.cos(rad)}" y="${cy + r * Math.sin(rad)}"
                  text-anchor="middle" dominant-baseline="middle"
                  font-size="16" font-weight="bold" font-family="inherit"
                  fill="${i === currentVal ? 'white' : PALETTE.ORANGE.main}">${i}</text>`;
              }).join('');
            }
          }
        } else if (circ) {
		  const climDv = e.mmi_detailView || 0;
		  if (climDv === 11) {
			$scope.display.mainLabel = T('Centre air vent');
			const level = (e.mmiscroll || 1) - 1;
			const maxVal = 6;
			updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
			circ.classList.add('climate-active');
			circ.textContent = '';
			if (dial) {
			  dial.style.display = 'block';
			  dial.style.bottom = '11px';
			  const cx = 90, cy = 90, r = 80;
			  dial.innerHTML = Array.from({ length: maxVal + 1 }, (_, i) => {
				const angle = (i / maxVal) * 270 - 225;
				const rad   = angle * Math.PI / 180;
				const x = cx + r * Math.cos(rad);
				const y = cy + r * Math.sin(rad);
				const color = i === level ? 'white' : PALETTE.ORANGE.main;
				if (i === 0) {
				  return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
					font-size="14" font-weight="bold" font-family="inherit" fill="${color}">${T('cooler')}</text>`;
				} else if (i === maxVal) {
				  return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
					font-size="14" font-weight="bold" font-family="inherit" fill="${color}">${T('warmer')}</text>`;
				} else {
				  return `<circle cx="${x}" cy="${y}" r="4" fill="${color}" />`;
				}
			  }).join('');
			}
		  } else {
			updateStyle('.value-indicator-4', { display: 'flex', transform: 'translateX(-20px)' });
			if (e.mmiscroll === 4) circ.classList.add('center-vent-selected');
			else circ.classList.remove('center-vent-selected');
			if (dial) dial.style.display = 'none';
		  }
		}

        for (let i = 1; i <= 6; i++) {
          updateStyle(`.menu-item-${i}`, {
            display: (isActive && (!isAir || i !== 4)) || (e.mmi_detailView || 0) === 11 ? 'none' : 'block',
            color:     i === e.mmiscroll ? 'white' : PALETTE.ORANGE.main,
            transform: (i === 4 && isAir) ? 'translate(20px, -15px)' : 'translateX(20px)'
          });
          if (i !== 4) updateStyle(`.value-box-${i}`, {
            display: isActive || (e.mmi_detailView || 0) === 11 ? 'none' : 'inline-flex',
            backgroundColor: i === e.mmiscroll ? 'white' : PALETTE.ORANGE.main,
            color: 'black',  transform: 'translateX(-20px)'
          });
        }
		
		if (items.length <= 4) {
		  updateStyle('.value-box-5', { display: 'none' });
		  updateStyle('.value-box-6', { display: 'none' });
		}

        if (isAir) {
          updateStyle('.menu-item-4', { color: (isPass ? airflow2 : airflow1) === 0 ? 'white' : PALETTE.ORANGE.main });
        } else if (!isActive && (e.mmi_detailView || 0) !== 11) {
          setScrollOverlay(e.mmiscroll, PALETTE.ORANGE.main, { leftOffset: 23 });
        }

        updateStyle('body', { backgroundImage: `url('${(e.mmi_detailView || 0) === 11 && !isActive ? 'orange_alt_line_no4_ui.png' : 'orange_alt_no4_ui.png'}')` });
      },

      [MENU.CAR]: (e, d) => {
        const activeSub = e.mmi_activeSubmenu || 0;
        Object.assign($scope.display, { title: T('Car'), cornerBR: T('Version'), cornerBL: T('Systems') });

        const pctStyle  = { display: 'block', color: 'red', textAlign: 'center' };
        const infoStyle = { display: 'block', color: 'red', left: '0', right: '0', textAlign: 'center' };

        applyTheme(PALETTE.RED, SUBMENU_CORNER[activeSub] || null);

        if (activeSub === 3) {
          const dv = e.mmi_detailView || 0;
          Object.assign($scope.display, { mainLabel: e.mmi_detailLabel || '' });

          if (dv === 1) {
            Object.assign($scope.display, {
              menuItem4: '0%', menuItem5: '50%', menuItem6: '100%',
              isCarBatteryMenu: true, batterySegments: Math.round((e.battery || 1.0) * 10)
            });
            updateStyle('.menu-item-4', { ...pctStyle, transform: 'translate(-135px, 19px)' });
            updateStyle('.menu-item-5', { ...pctStyle, transform: 'translate(0px, -9px)'    });
            updateStyle('.menu-item-6', { ...pctStyle, transform: 'translate(135px, -37px)' });
          } else if (dv === 2) {
            Object.assign($scope.display, {
              menuItem2: T('The required data for'),
              menuItem3: T('the service interval display'),
              menuItem4: T('are not yet available.')
            });
            [2, 3, 4].forEach(i => updateStyle(`.menu-item-${i}`, pctStyle));
          } else if (dv === 3) {
            $scope.display.menuItem3 = 'WAUZZZ4F57N123456';
            updateStyle('.menu-item-3', pctStyle);
          } else if (dv === 5) {
            setMenuItems(MENU_ITEMS.CAR_CENTRAL_LOCKING, e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            setScrollOverlay(e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            const lockStates = [e.lockInclude_FR ?? 1, e.lockInclude_RL ?? 1, e.lockInclude_RR ?? 1, e.lockInclude_trunk ?? 1, e.centralLock];
            lockStates.forEach((locked, idx) => {
              const slot = idx + 2;
              if (idx < (MENU_ITEMS.CAR_CENTRAL_LOCKING || []).length) {
                $scope.display[`menuValue${slot}`] = locked ? T('on') : T('off');
                updateStyle(`.value-box-${slot}`, { display: 'inline-flex', backgroundColor: slot === e.mmiscroll + 1 ? 'white' : PALETTE.RED.main, color: 'black', transform: 'none' });
              }
            });
		} else if (dv === 6) {
		  const pressures = d.customModules?.tireData?.pressures || {};
		const isBar = units.uiUnitPressure === 'bar';
		const fmt = (raw) => {
		  if (!raw) return '---';
		  const val = isBar ? raw / 100 : (raw / 100) * 14.504;
		  return val.toFixed(isBar ? 1 : 0) + (isBar ? ' bar' : ' psi');
		};
		const pressureState = (raw) => {
		  const bar = raw / 100;
		  return bar < 1.8 ? 'red' : bar < 2.1 ? 'yellow' : 'green';
		};
		  const stateColor  = { red: PALETTE.RED.main, yellow: PALETTE.YELLOW.main, green: PALETTE.GREEN.main };
		  const stateSuffix = { red: '_red', yellow: '_yellow', green: '' };
		  const items = [
			{ key: 'FL', imgBase: 'FL', slot: 1, status: SEL.status1, transform: 'translate(-100px, 28px)', mirror: false },
			{ key: 'FR', imgBase: 'FL', slot: 2, status: SEL.status2, transform: 'translate(100px,  0px)',  mirror: true  },
			{ key: 'RL', imgBase: 'RL', slot: 3, status: SEL.status3, transform: 'translate(-100px, 57px)', mirror: false },
			{ key: 'RR', imgBase: 'RL', slot: 4, status: SEL.status4, transform: 'translate(100px,  29px)', mirror: true  },
		  ];
		  items.forEach(({ key, imgBase, slot, status, transform, mirror }) => {
			const state  = pressureState(pressures[key] || 0);
			const imgUrl = `tire_pressure_${imgBase}${stateSuffix[state]}.png`;
			$scope.display[`menuItem${slot}`] = fmt(pressures[key]);
			updateStyle(`.menu-item-${slot}`, { display: 'block', color: stateColor[state], transform, textAlign: 'center' });
			updateStyle(status, { display: 'block', backgroundImage: `url('${imgUrl}')`, transform: mirror ? 'scaleX(-1)' : 'none' });
		  });
		} else if (dv === 7 || dv === 8) {
            // Brightness dial (side assist / background lighting)
            const level = (e.mmiscroll || 1) - 1;  // 0-4
            const maxVal = 4;
            const circ = find('.value-indicator-4');
            const dial = find('#circle-dial');
            if (circ) {
                updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
                circ.classList.add('sideassist-active');
                circ.textContent = '';
                if (dial) {
                    dial.style.display = 'block';
                    dial.style.bottom = '11px';
                    const cx = 90, cy = 90, r = 80;
                    dial.innerHTML = Array.from({ length: maxVal + 1 }, (_, i) => {
                        const angle = (i / maxVal) * 270 - 225;
                        const rad   = angle * Math.PI / 180;
                        const x = cx + r * Math.cos(rad);
                        const y = cy + r * Math.sin(rad);
                        const color = i === level ? 'white' : PALETTE.RED.main;
                        if (i === 0) {
                            return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle" font-size="14" font-weight="bold" font-family="inherit" fill="${color}">${T('dark')}</text>`;
                        } else if (i === maxVal) {
                            return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle" font-size="14" font-weight="bold" font-family="inherit" fill="${color}">${T('bright')}</text>`;
                        } else {
                            return `<circle cx="${x}" cy="${y}" r="4" fill="${color}" />`;
                        }
                    }).join('');
                }
            }
        } else if (dv === 9) { // Exterior lighting list view
          setMenuItems(MENU_ITEMS.CAR_EXT_LIGHTING || [], e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
          setScrollOverlay(e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });

          const extStates = [e.mmi_comingHomeActive ?? 1, e.mmi_leavingHomeActive ?? 1, e.mmi_drlActive ?? 1];

          const indicatorEl = find('.value-indicator-4');
          if (indicatorEl) {
            const isSelected = e.mmiscroll === 1;
            const isActive = extStates[0] === 1;

            updateStyle('.value-indicator-4', { display: 'flex', transform: 'none' });
            indicatorEl.classList.add('ext-lighting-indicator');
            indicatorEl.classList.toggle('active', isActive);
            indicatorEl.classList.toggle('center-vent-selected', isSelected);
          }

          // Populate on/off toggle boxes sequentially down for lines 3 & 4
          extStates.forEach((active, idx) => {
            const slot = idx + 2; 
            if (idx > 0 && idx < (MENU_ITEMS.CAR_EXT_LIGHTING || []).length) { 
              $scope.display[`menuValue${slot}`] = active ? T('on') : T('off');
              updateStyle(`.value-box-${slot}`, { 
                display: 'inline-flex', 
                backgroundColor: slot === e.mmiscroll + 1 ? 'white' : PALETTE.RED.main, 
                color: 'black', 
                transform: 'none' 
              });
            } else if (idx === 0) {
              updateStyle('.value-box-2', { display: 'none' });
            }
          });
        } else if (dv === 12) {
			$scope.display.mainLabel = T('coming home');
			// Coming home duration dial
			const level = (e.mmiscroll || 1) - 1;
			const maxVal = 6;
			const circ = find('.value-indicator-4');
			const dial = find('#circle-dial');
			if (circ) {
			  updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
			  circ.classList.add('sideassist-active');
			  circ.textContent = '';
			  if (dial) {
				dial.style.display = 'block';
				dial.style.bottom = '11px';
				const cx = 90, cy = 90, r = 80;
				dial.innerHTML = Array.from({ length: maxVal + 1 }, (_, i) => {
				  const angle = (i / maxVal) * 270 - 225;
				  const rad   = angle * Math.PI / 180;
				  const x = cx + r * Math.cos(rad);
				  const y = cy + r * Math.sin(rad);
				  const color = i === level ? 'white' : PALETTE.RED.main;
				  if (i === 0) {
					return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
					  font-size="14" font-weight="bold" font-family="inherit" fill="${color}">${T('off')}</text>`;
				  } else if (i === maxVal) {
					return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
					  font-size="14" font-weight="bold" font-family="inherit" fill="${color}">60 sec</text>`;
				  } else {
					return `<circle cx="${x}" cy="${y}" r="4" fill="${color}" />`;
				  }
				}).join('');
			  }
			}
			updateStyle('body', { backgroundImage: "url('red_line_noscroll_no12_ui.png')" });
		} else if (dv === 10) {
            // Windshield wipers – Service position toggle
            setMenuItems(MENU_ITEMS.CAR_WIPERS || [], e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            setScrollOverlay(e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            const serviceOn = e.mmi_wiperServicePos || 0;
            $scope.display.menuValue2 = serviceOn ? T('on') : T('off');
            updateStyle('.value-box-2', { display: 'inline-flex', backgroundColor: e.mmiscroll === 1 ? 'white' : PALETTE.RED.main, color: 'black', transform: 'none' });
		} else if (dv === 13) {
            // Parking system settings list
            setMenuItems(MENU_ITEMS.PARKING_SETTINGS || [], e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            setScrollOverlay(e.mmiscroll, PALETTE.RED.main, { startSlot: 2 });
            // Display value box on line 2 (slot 2)
            const dispMode = e.mmi_parkingDisplayMode || 0;
            const dispLabel = (dispMode === 1 && e.reverseCameraEnabled) ? T('Rear View') : T('Graphic');
            $scope.display.menuValue2 = dispLabel;
            updateStyle('.value-box-2', { display: 'inline-flex', backgroundColor: e.mmiscroll === 1 ? 'white' : PALETTE.RED.main, color: 'black', transform: 'none' });
            // Red circle indicators on slots 3-6, white fill when selected
            const indicatorSlots = [
              { sel: '.value-indicator-3', scroll: 2 },
              { sel: '.value-indicator-4', scroll: 3 },
              { sel: '.value-indicator-5', scroll: 4 },
              { sel: '.value-indicator-6', scroll: 5 }
            ];
            indicatorSlots.forEach(({ sel, scroll }) => {
              updateStyle(sel, { display: 'flex', transform: 'none' });
              const el = find(sel);
              if (el) el.classList.toggle('indicator-selected', e.mmiscroll === scroll);
            });
        } else if (dv >= 14 && dv <= 17) {
            // Parking volume/frequency 1-9 dial
            const dialLabels = { 14: T('Front volume'), 15: T('Front frequency'), 16: T('Rear volume'), 17: T('Rear frequency') };
            $scope.display.mainLabel = dialLabels[dv];
            const level = e.mmiscroll || 1;
            const maxVal = 9;
            const circ = find('.value-indicator-4');
            const dial = find('#circle-dial');
            if (circ) {
              updateStyle('.value-indicator-4', { display: 'flex', transform: 'scale(1.3) translateY(16px)' });
              circ.classList.add('sideassist-active');
              circ.textContent = '';
              if (dial) {
                dial.style.display = 'block';
                dial.style.bottom = '11px';
                const cx = 90, cy = 90, r = 80;
                dial.innerHTML = Array.from({ length: maxVal }, (_, i) => {
                  const val = i + 1;
                  const angle = (i / (maxVal - 1)) * 270 - 225;
                  const rad = angle * Math.PI / 180;
                  const x = cx + r * Math.cos(rad);
                  const y = cy + r * Math.sin(rad);
                  const color = val === level ? 'white' : PALETTE.RED.main;
                  return `<text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="middle"
                    font-size="16" font-weight="bold" font-family="inherit" fill="${color}">${val}</text>`;
                }).join('');
              }
            }
            updateStyle('body', { backgroundImage: "url('red_line_noscroll_no12_ui.png')" });
		} else {
            setMenuItems(MENU_ITEMS.CAR_SYSTEMS, e.mmiscroll, PALETTE.RED.main);
            setScrollOverlay(e.mmiscroll, PALETTE.RED.main);
            // Add ᐅ arrows to all car system items
            const carItems = MENU_ITEMS.CAR_SYSTEMS || [];
            const carSel = Math.max(1, e.mmiscroll || 1) - 1;
            const carWinStart = carItems.length > 6 ? Math.floor(carSel / 6) * 6 : 0;
            for (let slot = 1; slot <= 6; slot++) {
              const idx = carWinStart + (slot - 1);
              if (idx < carItems.length) {
                updateStyle(`.menu-item-${slot}`, { right: '130px' });
                $scope.display[`menuValue${slot}`] = 'ᐅ';
                updateStyle(`.value-box-${slot}`, {
                  display: 'inline-flex', backgroundColor: 'transparent',
                  color: idx === carSel ? 'white' : PALETTE.RED.main,
                  padding: '0', right: '100px', transform: 'none', fontSize: '22px'
                });
              }
            }
          }

          updateStyle('body', { backgroundImage: `url('${dv > 0 ? 'red_line_no12_ui.png' : 'red_no12_ui.png'}')` });
          activateSubmenuSelector(3, 'select2.png');
        } else if (activeSub === 4) {
          Object.assign($scope.display, {
            mainLabel: D('VERSION_INFO', 'mainLabel', T('Version')),
            menuItem1: D('VERSION_INFO', 'line1', 'SW: C6-HU 55.7.0 0835'),
            menuItem2: D('VERSION_INFO', 'line2', 'HW: C6-HU 6350D2.0'),
            menuItem3: D('VERSION_INFO', 'line3', 'FC SW: 03501AFC6AB320870'),
            menuItem4: D('VERSION_INFO', 'line4', 'FC PS: 0870 FC HW: H07')
          });
          [1, 2, 3, 4].forEach((i, off) => updateStyle(`.menu-item-${i}`, { ...infoStyle, transform: `translateY(${28 + off * 9}px)` }));
          updateStyle('body', { backgroundImage: "url('red_line_no12_ui.png')" });
          activateSubmenuSelector(4, 'select2.png');
        } else {
          const suspItems = MENU_ITEMS.CAR_SUSPENSION || [];
          const isSport   = e.mmi_suspensionType === 'sport';
          Object.assign($scope.display, {
            mainLabel: isSport ? T('sports suspension plus') : T('adaptive air suspension')
          });
          suspItems.forEach((label, i) => { $scope.display[`menuItem${i + 2}`] = label; });

          const suspLayout = isSport ? [
            { slot: 3, scroll: 1, tx: 'translate(145px, 0px)' },
            { slot: 4, scroll: 2, tx: 'translate(160px, 0px)' },
            { slot: 5, scroll: 3, tx: 'translate(145px, 0px)' },
          ] : [
            { slot: 2, scroll: 1, tx: 'translate(145px, 15px)' },
            { slot: 3, scroll: 2, tx: 'translate(160px, 15px)' },
            { slot: 4, scroll: 3, tx: 'translate(160px, 15px)' },
            { slot: 5, scroll: 4, tx: 'translate(145px, 15px)' },
          ];

          suspLayout.forEach(({ slot, scroll, tx }) => {
            $scope.display[`menuItem${slot}`] = suspItems[scroll - 1];
            updateStyle(`.menu-item-${slot}`, {
              display: 'block',
              color: e.mmiscroll === scroll ? 'white' : PALETTE.RED.main,
              transform: tx
            });
          });
          updateStyle('body',      { backgroundImage: "url('red_line_no12_ui.png')" });
          updateStyle(SEL.overlay, {
            display: 'block',
            backgroundImage: isSport ? "url('suspension_sport.png')" : "url('suspension.png')"
          });
        }
      },

      [MENU.NAME]: (e) => {
        if (e.phoneEnabled != 1) {
          Object.assign($scope.display, {
            title:     T('Telephone'),
            mainLabel: T('Note'),
            menuItem2: T('Telephone is not installed.')
          });
          updateStyle('body',          { backgroundImage: "url('green_no_ui.png')" });
          updateStyle('.menu-item-2',  { display: 'block', color: PALETTE.GREEN.main, textAlign: 'left', left: '105px' });
          updateStyle('.center-label', { textAlign: 'left', left: '105px' });
          applyTheme(PALETTE.GREEN, null);
          return;
        }

        const activeSub = e.mmi_activeSubmenu || 0;
        const contacts  = MENU_ITEMS.CONTACTS || [];
        Object.assign($scope.display, { title: T('Directory'), cornerTL: T('Import'), cornerBR: T('Edit'), cornerBL: T('Options') });
        applyTheme(PALETTE.GREEN, SUBMENU_CORNER[activeSub] || null);

        const subConfigs = {
          0: { items: [T('Find entry'), ...contacts],                        bg: 'green_no2_ui.png',      startSlot: 1 },
          1: { items: [T('Find entry'), T('Import all entries'), ...contacts],  bg: 'green_line_no2_ui.png', startSlot: 2 },
          3: { items: MENU_ITEMS.NAME_EDIT,                               bg: 'green_no2_ui.png',      startSlot: 1 },
          4: { items: MENU_ITEMS.NAME_CALL,                               bg: 'green_no2_ui.png',      startSlot: 1 }
        };
        const cfg = subConfigs[activeSub] || subConfigs[0];
        if (activeSub === 1) $scope.display.mainLabel = T('From phone book');

        updateStyle('body', { backgroundImage: `url('${cfg.bg}')` });
        setMenuItems(cfg.items, e.mmiscroll, PALETTE.GREEN.main, { startSlot: cfg.startSlot });
        setScrollOverlay(e.mmiscroll, PALETTE.GREEN.main, { startSlot: cfg.startSlot });
        if (activeSub >= 1) activateSubmenuSelector(activeSub, 'select_green2.png');
      },

      [MENU.TEL]: (e) => {
        const phoneDisabled = e.phoneEnabled != 1;
        if (phoneDisabled) {
          Object.assign($scope.display, {
            title:     T('Telephone'),
            mainLabel: T('Note'),
            menuItem2: T('Telephone is not installed.')
          });
          updateStyle('body',          { backgroundImage: "url('green_no_ui.png')" });
          updateStyle('.menu-item-2',  { display: 'block', color: PALETTE.GREEN.main, textAlign: 'left', left: '105px' });
          updateStyle('.center-label', { textAlign: 'left', left: '105px' });
          applyTheme(PALETTE.GREEN, null);
          return;
        }

        const activeSub      = e.mmi_activeSubmenu || 1;
        const contacts       = MENU_ITEMS.CONTACTS || [];
        const selectedContact = contacts[(e.mmiscroll || 1) - 1] || contacts[0] || '';
        Object.assign($scope.display, { title: T('Telephone - T-Mobile'), cornerTL: T('Memory'), cornerBR: T('Dial'), cornerBL: T('End call') });
        applyTheme(PALETTE.GREEN, SUBMENU_CORNER[activeSub] || null);

        if (activeSub === 1) {
          $scope.display.mainLabel = T('Phone book');
          updateStyle('body', { backgroundImage: "url('green_line_no2_ui.png')" });
          activateSubmenuSelector(1, 'select_green2.png');
          setMenuItems(contacts, e.mmiscroll, PALETTE.GREEN.main, { startSlot: 2 });
          setScrollOverlay(e.mmiscroll, PALETTE.GREEN.main, { startSlot: 2 });
          updateStyle(SEL.overlay, { display: 'block', backgroundImage: "url('dial.png')" });
        } else if (activeSub === 3) {
          Object.assign($scope.display, { mainLabel: selectedContact, menuItem1: T('End call') });
          updateStyle('.menu-item-1', { display: 'block', color: 'white', left: '0', right: '0', textAlign: 'center', transform: 'translateY(58px)' });
          updateStyle('body', { backgroundImage: "url('green_line_no2_ui.png')" });
          activateSubmenuSelector(3, 'select_green2.png');
          updateStyle(SEL.overlay, { display: 'block', backgroundImage: "url('dial3.png')" });
        } else if (activeSub === 4) {
          const inCall = e.mmi_detailView === 1;
          Object.assign($scope.display, { mainLabel: selectedContact, menuItem1: inCall ? T('Connected') : T('Dialing') });
          updateStyle('.menu-item-1', { display: 'block', color: 'white', left: '0', right: '0', textAlign: 'center', transform: 'translateY(58px)' });
          updateStyle('body', { backgroundImage: "url('green_line_no2_ui.png')" });
          activateSubmenuSelector(4, 'select_green2.png');
          updateStyle(SEL.overlay, { display: 'block', backgroundImage: inCall ? "url('dial5.png')" : "url('dial4.png')" });
        }
      },

      [MENU.PARKING_GRAPHIC]: (e, d, isCam) => {
        const inReverse = (e.reverse || 0) !== 0;
        const hasCam    = e.reverseCameraEnabled && inReverse;
        const sensorsOn = e.button_parkingsensors;

        $scope.display.bottomMainLabel = T('Look! Safe to move?');
        updateStyle('.bottom-center-label', { color: PALETTE.RED.main, transform: 'none' });
        $scope.display.cornerBL = T('Settings');
        $scope.display.cornerBR = !sensorsOn ? '' : isCam ? T('Graphic') : hasCam ? T('Rear View') : '';
        if (!isCam) $scope.display.title = T('Audi parking system');

        const parkingBg = isCam ? 'hud.png' : hasCam ? 'parking_system_cam.png' : 'parking_system.png';
        updateStyle('body',       { backgroundImage: `url('${parkingBg}')` });
        updateStyle(SEL.parking,  { display: 'block', transform: isCam ? 'rotate(90deg) scale(0.66) translate(-18px, 272px)' : 'none' });
        updateStyle(SEL.overlay,  {
          display:         e.frontParkingSensorsEnabled && !isCam ? 'block' : 'none',
          backgroundImage: e.frontParkingSensorsEnabled && !isCam ? "url('parking_front_overlay.png')" : 'none'
        });
        updateStyle('#front-sensors-group', { transform: isCam ? 'translate(12px,-2px)' : 'none' });

        $scope.display.isParkingVisible = true;

        const processBumper = (hits, offset, isActive, outerLevels, innerLevels) => {
          if (!isActive || !hits?.length) return;
          const size = Math.ceil(hits.length / 4);
          for (let i = 0; i < 4; i++) {
            const slice = hits.slice(i * size, (i + 1) * size);
            $scope.display[`proximity${i + 1 + offset}`] = getProximityLevel(
              slice.length ? Math.min(...slice) : 100, (i === 0 || i === 3) ? outerLevels : innerLevels
            );
          }
        };
        processBumper(e.parkingSensorHits?.rearBumper,  0, e.button_parkingsensors, 3, 7);
        processBumper(e.parkingSensorHits?.frontBumper, 4, e.button_parkingsensors, 4, 5);
        applyTheme(PALETTE.RED);
      }
    };
	
	$window.setup = (setupData) => {
	  for (let dk in setupData) {
		if (typeof dk === 'string' && dk.startsWith('uiUnit')) {
		  units[dk] = setupData[dk];
		}
	  }
	  if (setupData.bootscreenImage) {
		const el = document.getElementById('bootscreen');
		if (el) el.style.backgroundImage = `url('${setupData.bootscreenImage}')`;
	  }
	};

    $window.updateData = (data) => {
      $scope.$evalAsync(() => {
        clearInterface();
        const e = data.electrics;
        $scope.cachedElectrics = e;
        const ignition = e.ignitionLevel || 0;

        setBootscreen(ignition);

        const timeEl = document.querySelector('.time-display');
        if (timeEl) timeEl.style.transform = ignition < 2 ? 'none' : 'translateX(15px)';

        if (ignition < 2) {
          $scope.state.showTime    = true;
          $scope.display.timestamp = new Date();
          return;
        }
		
		if (e.mmi_menu_items && e.mmi_menu_items !== lastMenuItemsJson) {
		  try {
			MENU_ITEMS = JSON.parse(e.mmi_menu_items);
			lastMenuItemsJson = e.mmi_menu_items;
		  } catch (_) {
			lastMenuItemsJson = '';
		  }
		}

        // Lua owns all routing logic — mmi_activeScreen is set there each frame.
        const active = e.mmi_activeScreen ?? e.mmiMenu ?? MENU.MEDIA;
        const isCam  = active === MENU.REVERSE_CAMERA;

        $scope.state.showTime    = active < 100;
        $scope.display.timestamp = $scope.state.showTime ? new Date() : '';

        const handler = HANDLERS[isCam ? MENU.PARKING_GRAPHIC : active] || HANDLERS[MENU.MEDIA];
        handler(e, data, isCam);
      });
    };

    (function init() {
      const clock = () => {
        $scope.display.timestamp = $scope.state.showTime ? new Date() : '';
        $timeout(clock, 1000);
      };
      clock();

      $window.preloads = [
        'hud.png', 'green_no_ui.png',
        'red_line_ui.png', 'red_line_no12_ui.png', 'red_line_no13_ui.png',
        'red_ui.png', 'red_no12_ui.png', 'red_alt_no4_ui.png',
        'orange_ui.png', 'orange_line_ui.png', 'orange_alt_no4_ui.png','orange_alt_line_no4_ui.png',
        'green_ui.png', 'green_no2_ui.png', 'green_line_no2_ui.png', 'green_line2_no2_ui.png',
        'suspension.png', 'suspension_sport.png', 'fan_and_heatedseats.png', 'airflow.png',
        'dial.png', 'dial3.png', 'dial4.png', 'dial5.png',
        'select.png', 'select_green2.png', 'select2.png',
        'parking_system_cam.png', 'parking_system.png', 'parking_front_overlay.png',
        ...Array.from({ length: 4 }, (_, i) => `front_1_${i + 1}.png`),
        ...Array.from({ length: 5 }, (_, i) => `front_2_${i + 1}.png`),
        'fan_overlay.png', 'heatedseats_overlay.png',
		
		...Array.from({ length: 7 }, (_, i) => [`airflow${i + 1}.png`, `airflow${i + 1}_2.png`]).flat(),
		
		...['FL', 'RL'].flatMap(pos =>
		  ['', '_yellow', '_red'].map(s => `tire_pressure_${pos}${s}.png`)
		),
		
        ...['mute', 'low-volume', 'high-volume'].flatMap(t =>
          ['', '-orange', '-blue', '-green'].map(c => `${t}${c}-icon.png`)
        )
		
      ].map(s => { const i = new Image(); i.src = s; return i; });
    })();
  });