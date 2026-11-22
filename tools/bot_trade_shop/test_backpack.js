const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const events = {};
const colored = {style:{},getAttribute:()=> '8650ac'};
const unsafe = {style:{},getAttribute:()=> 'red;background:url(evil)'};
const grid = {querySelector:()=>null,addEventListener:(name,fn)=>events[name]=fn};
let removed=false,delay=0,expire;
const toast={remove(){removed=true;}};
vm.runInNewContext(fs.readFileSync(__dirname+'/backpack.js','utf8'), {
    document:{querySelector:s=>s==='.purchase-toast'?toast:null,querySelectorAll:selector=>selector==='[data-color]'?[colored,unsafe]:[grid]},
    window:{addEventListener:()=>{},setTimeout(fn,ms){expire=fn;delay=ms;}}
});
assert.equal(delay,3000);assert.equal(removed,false);expire();assert.equal(removed,true);
assert.equal(colored.style.color,'#8650ac');
assert.equal(unsafe.style.color,undefined);
const a={checked:false,matches:()=>true},b={checked:false,matches:()=>true};
function click(input){a.checked=false;b.checked=false;input.checked=true;events.click({target:input});events.change({target:input});}
click(a);assert.equal(a.checked,true);
click(a);assert.equal(a.checked,false);
click(a);click(b);assert.equal(a.checked,false);assert.equal(b.checked,true);
click(b);assert.equal(b.checked,false);
console.log('PASS validated colors, select/deselect/reselect/switch');
