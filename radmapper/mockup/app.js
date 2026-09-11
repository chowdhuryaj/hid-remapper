'use strict';
function resizeSlots(slots, count) {
  if (![4, 8].includes(count) || ![4, 8].includes(slots.length)) throw new Error('Use 4 or 8 directions');
  return Array.from({length: count}, (_, i) => {
    const from = count === slots.length ? i : count === 8 ? (i % 2 === 0 ? i / 2 : -1) : i * 2;
    return from >= 0 ? {...slots[from]} : {label: '', action: 'none', shortcut: ''};
  });
}
if (typeof module !== 'undefined') module.exports = {resizeSlots};
if (typeof document !== 'undefined') {
  const $ = id => document.getElementById(id);
  let slots = ['Next series', 'Measure', 'Previous series', 'Zoom fit'].map(label => ({label, action:'none', shortcut:''}));
  let selected = 0, dirty = false, recording = false, paused = false, routed = false;
  const directions = () => slots.length === 4 ? ['Up','Right','Down','Left'] : ['Up','Up-right','Right','Down-right','Down','Down-left','Left','Up-left'];
  const say = text => {$('menu-status').textContent = text;};
  const markDirty = () => {dirty = true; say('Draft changed · Save when ready');};
  function route() {
    recording = false;
    $('record').textContent = 'Record shortcut';
    const pages = ['home','menus','binding','guide'];
    const page = pages.includes(location.hash.slice(1)) ? location.hash.slice(1) : 'home';
    document.querySelectorAll('[data-page]').forEach(el => {el.hidden = el.id !== page;});
    document.querySelectorAll('nav a').forEach(a => {
      if(a.hash === '#' + page) a.setAttribute('aria-current','page'); else a.removeAttribute('aria-current');
    });
    $('binding-menu').value = $('menu-name').value.trim() || 'Unnamed menu';
    if(routed) $('main').focus({preventScroll:true});
    routed = true;
  }
  function drawWheel(container, practice = false) {
    container.replaceChildren();
    container.classList.toggle("eight",slots.length === 8);
    const center = document.createElement('button');
    center.type = 'button'; center.className = 'center'; center.textContent = practice ? 'Cancel' : 'Center\ncancels';
    center.setAttribute('aria-label', practice ? 'Cancel practice' : 'Center cancels a radial menu');
    center.addEventListener('click', () => {
      if(practice) {$('practice-result').textContent = 'Cancelled · No command sent';}
      else say('Release in the center to cancel on Windows.');
    });
    container.append(center);
    slots.forEach((slot,i) => {
      const button = document.createElement('button');
      button.type = 'button';
      const a = i * 2 * Math.PI / slots.length;
      const radius = slots.length === 8 ? 40 : 36;
      button.style.left = (50 + radius * Math.sin(a)) + '%';
      button.style.top = (50 - radius * Math.cos(a)) + '%';
      const label = document.createElement('strong'); label.textContent = directions()[i];
      const detail = document.createElement('span'); detail.textContent = slot.label || 'Add command';
      button.append(label,detail);
      button.title = directions()[i] + ": " + (slot.label || "Add command");
      button.setAttribute('aria-label', directions()[i] + ': ' + (slot.label || 'Empty') + (slot.action === 'none' ? ', disabled command' : ''));
      if(!practice){button.classList.toggle('selected',i === selected);button.setAttribute('aria-pressed',String(i === selected));}
      button.addEventListener('click',()=>{
        if(practice){$('practice-result').textContent = paused ? 'Preview paused · No command sent' : slot.action === 'none' ? 'Empty direction · No command sent' : 'Would run: ' + slot.label + ' · No command sent';}
        else {selected = i; refresh(); $('command-label').focus();}
      });
      container.append(button);
    });
  }
  function refresh() {
    drawWheel($('wheel'));
    const slot = slots[selected];
    $('direction-heading').textContent = directions()[selected] + ' · Command';
    $('command-label').value = slot.label;
    $('action').value = slot.action;
    $('shortcut').value = slot.shortcut;
    $('shortcut-group').hidden = slot.action !== 'keys';
    $('size').value = String(slots.length);
  }
  function update() {
    slots[selected] = {label:$('command-label').value, action:$('action').value, shortcut:$('shortcut').value};
    $('shortcut-group').hidden = slots[selected].action !== 'keys';
    if(slots[selected].action !== 'keys') {recording = false; $('record').textContent = 'Record shortcut';}
    drawWheel($('wheel')); markDirty();
  }
  ['command-label','action','shortcut'].forEach(id=>$(id).addEventListener('input',update));
  ['menu-name','program'].forEach(id=>$(id).addEventListener('input',markDirty));
  function resize(count){slots = resizeSlots(slots,count);selected = 0;refresh();markDirty();}
  $('size').addEventListener('change',()=>{
    const count = Number($('size').value);
    if(count === 4 && slots.length === 8 && slots.some((s,i)=>i%2 && (s.label.trim() || s.action !== 'none'))){
      $('size').value = '8'; $('resize-dialog').showModal();
    } else resize(count);
  });
  $('cancel-resize').addEventListener('click',()=>$('resize-dialog').close());
  $('confirm-resize').addEventListener('click',()=>{resize(4);$('resize-dialog').close();});
  $('record').addEventListener('click',()=>{
    recording = !recording;
    $('record').textContent = recording ? 'Press your shortcut…' : 'Record shortcut';
    say(recording ? 'Recording in this page · Escape cancels' : 'Recording cancelled');
  });
  document.addEventListener('keydown',event=>{
    if(!recording) return;
    event.preventDefault(); event.stopPropagation();
    if(event.key === 'Escape'){recording = false;$('record').textContent = 'Record shortcut';say('Recording cancelled');return;}
    if(['Control','Alt','Shift','Meta'].includes(event.key))return;
    const key = event.key === ' ' ? 'Space' : event.key.length === 1 ? event.key.toUpperCase() : event.key;
    $('shortcut').value = [event.ctrlKey?'Ctrl':'',event.altKey?'Alt':'',event.shiftKey?'Shift':'',event.metaKey?'Win':'',key].filter(Boolean).join(' + ');
    recording = false;$('record').textContent = 'Record shortcut';update();
  },true);
  $('save-menu').addEventListener('click',()=>{
    const name = $('menu-name').value.trim();
    if(!name){say('Give your menu a name before saving.');$('menu-name').focus();return;}
    const invalid = slots.findIndex(s=>s.action === 'keys' && !s.shortcut.trim());
    if(invalid >= 0){selected = invalid;refresh();say(directions()[invalid] + ' needs a shortcut. Record one or choose Disabled.');$('shortcut').focus();return;}
    for(const s of slots) if(s.action !== 'none' && !s.label.trim()) s.label = s.action === 'keys' ? 'Send keys' : s.action === 'ps_dictate' ? 'Dictate' : 'Next field';
    dirty = false;refresh();$('binding-menu').value = name;
    const live = slots.filter(s=>s.action !== 'none').length;
    say('Saved for this preview session · ' + live + ' of ' + slots.length + ' directions assigned');
  });
  $('practice').addEventListener('click',()=>{drawWheel($('practice-wheel'),true);$('practice-result').textContent = 'Choose a direction. Escape closes practice.';$('practice-dialog').showModal();});
  $('close-practice').addEventListener('click',()=>$('practice-dialog').close());
  $('binding-form').addEventListener('submit',e=>{e.preventDefault();$('binding-status').textContent = 'Preview only: ' + $('trigger').selectedOptions[0].text + ' ' + $('button-choice').value + ' → ' + $('binding-menu').value;});
  $('trigger').addEventListener('change',()=>{$('trigger-hint').textContent = $('trigger').value === 'hold' ? 'Hold to open. Release to choose. Release in the center to cancel.' : 'Tap opens the menu. Rest in a direction to select. Escape cancels.';});
  $('pause').addEventListener('click',()=>{paused = !paused;$('pause').setAttribute('aria-pressed',String(paused));$('pause').textContent = paused?'Resume preview':'Pause preview';$('engine-status').textContent = paused?'Preview paused':'Preview active';});
  $('help-button').addEventListener('click',()=>{location.hash = 'guide';});
  window.addEventListener('hashchange',route);
  window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
  refresh();route();
}
