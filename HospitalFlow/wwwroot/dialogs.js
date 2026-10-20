'use strict';
// A separate dialog keeps confirmations from replacing an open workspace form.
const appDialogQueue=[];
let appDialogActive=false;
function appDialog({title='HospitalFlow',message='',input=false,confirmText='Continue',cancel=true}={}){
 return new Promise(resolve=>{appDialogQueue.push({title,message,input,confirmText,cancel,resolve});showNextAppDialog();});
}
function showNextAppDialog(){
 if(appDialogActive||!appDialogQueue.length)return;
 appDialogActive=true;
 const item=appDialogQueue.shift(),dialog=document.getElementById('app-dialog'),form=document.getElementById('app-dialog-form'),field=document.getElementById('app-dialog-input');
 const priorFocus=document.activeElement;
 document.getElementById('app-dialog-title').textContent=item.title;
 document.getElementById('app-dialog-message').textContent=item.message;
 document.getElementById('app-dialog-input-label').hidden=!item.input;
 field.value='';field.required=item.input;field.disabled=!item.input;
 document.getElementById('app-dialog-error').textContent='';
 const accept=document.getElementById('app-dialog-accept'),cancel=document.getElementById('app-dialog-cancel');
 accept.textContent=item.confirmText;cancel.hidden=!item.cancel;
 let settled=false;
 function finish(value){if(settled)return;settled=true;dialog.close();form.onsubmit=null;dialog.oncancel=null;appDialogActive=false;if(priorFocus?.isConnected)priorFocus.focus();item.resolve(value);showNextAppDialog();}
 form.onsubmit=event=>{event.preventDefault();if(item.input&&!field.value.trim()){document.getElementById('app-dialog-error').textContent='Enter a reason or handover note.';field.focus();return;}finish(item.input?field.value.trim():true);};
 cancel.onclick=()=>finish(item.input?null:false);
 dialog.oncancel=event=>{event.preventDefault();finish(item.input?null:false);};
 dialog.showModal();(item.input?field:item.cancel?cancel:accept).focus();
}
function appConfirm(message,title='Confirm action'){return appDialog({title,message,confirmText:'Confirm'});}
function appPrompt(message,title='Referral decision'){return appDialog({title,message,input:true,confirmText:'Save decision'});}
// Preserve HTML constraint validation, but replace the browser's validation bubble.
let validationNoticePending=false;
document.addEventListener('invalid',event=>{
 event.preventDefault();
 if(validationNoticePending||event.target.closest('#app-dialog'))return;
 validationNoticePending=true;
 const field=event.target;
 const label=field.labels?.[0]?.textContent?.replace(/\*/g,'').trim()||field.name||'This field';
 appDialog({title:'Check your details',message:label+': '+field.validationMessage,confirmText:'Review field',cancel:false}).then(()=>{validationNoticePending=false;if(field.isConnected)field.focus();});
},true);
