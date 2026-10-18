'use strict';
function applyTheme(theme,notify=false){
 theme=theme==='Dark'?'Dark':'Default';document.documentElement.dataset.theme=theme;
 try{localStorage.setItem('hospitalflow.theme',theme);}catch{}
 const button=document.getElementById('theme-toggle');if(button){button.textContent=theme==='Dark'?'☀ Default':'☾ Dark';button.setAttribute('aria-pressed',String(theme==='Dark'));}
 if(notify)document.dispatchEvent(new CustomEvent('hospitalflow:theme-changed',{detail:theme}));
}
try{applyTheme(localStorage.getItem('hospitalflow.theme'));}catch{applyTheme('Default');}
function toggleTheme(){applyTheme(document.documentElement.dataset.theme==='Dark'?'Default':'Dark',true);}
document.addEventListener('dblclick',toggleTheme);
document.addEventListener('DOMContentLoaded',()=>{
 document.getElementById('theme-toggle').onclick=toggleTheme;applyTheme(document.documentElement.dataset.theme);
 const markRequired=()=>document.querySelectorAll('label').forEach(label=>{const control=label.querySelector('input[required],select[required],textarea[required]');if(control&&!label.querySelector('.required-mark')){const star=document.createElement('span');star.className='required-mark';star.textContent=' *';star.setAttribute('aria-hidden','true');label.insertBefore(star,control);}});
 markRequired();new MutationObserver(markRequired).observe(document.body,{childList:true,subtree:true});
});
