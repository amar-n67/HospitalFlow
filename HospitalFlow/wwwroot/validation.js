'use strict';
const passwordHelp='Use 6–128 characters, including an uppercase letter, a lowercase letter and a symbol. Do not use common passwords, your name, username or email.';
function validateEmail(value){
 const email=String(value||'').trim().toLowerCase();
 const expression=/^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;
 if(email.length>150||email.split('@')[0].length>64||!expression.test(email))throw Error('Enter a valid email address, such as name@gmail.com. Include @ and a complete domain.');return email;
}
function validatePassword(value,name='',email=''){
 if(value.length<6||value.length>128)throw Error('Password must contain 6–128 characters.');
 if(!/[A-Z]/.test(value))throw Error('Password must contain an uppercase letter (A–Z).');
 if(!/[a-z]/.test(value))throw Error('Password must contain a lowercase letter (a–z).');
 if(!/[\p{P}\p{S}]/u.test(value))throw Error('Password must contain a symbol, such as @, # or !.');
 const normalize=text=>String(text).replace(/[^\p{L}\p{N}]/gu,'').toLowerCase();
 const normalized=normalize(value),letters=normalized.replace(/[^\p{L}]/gu,'');
 if(normalized.includes('password')||['pass','passwords','qwerty','admin','administrator','welcome','letmein','changeme','abc','abcdef'].includes(letters))throw Error('Choose a less common password. Password, passwords and pass variations are not allowed.');
 if([...name.split(/\s+/),name,email.split('@')[0],email].map(normalize).some(identity=>identity.length>0&&(normalized===identity||(identity.length>=3&&normalized.includes(identity)))))throw Error('Password must not contain your name, username or email address.');
}
