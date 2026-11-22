'use strict';
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const listeners={},scroll={};let pending,requests=0;
let rect={left:20,right:180,top:40,bottom:240};
const url='https://backpack.tf/item/123';
const button={focus(){listeners.focus();},getAttribute:n=>n==='data-market-url'?url:'fixture',closest:()=>({getBoundingClientRect:()=>rect}),addEventListener:(n,f)=>listeners[n]=f};
const tip={style:{},hidden:true,offsetWidth:330,offsetHeight:200,addEventListener(){},textContent:''};
const dialogListeners={},copyListeners={},closeListeners={};
const overlay={hidden:true,addEventListener:(n,f)=>dialogListeners[n]=f};
const field={value:'',focus(){document.activeElement=field;},select(){this.selected=true;}};
const closeButton={focus(){document.activeElement=closeButton;},addEventListener:(n,f)=>closeListeners[n]=f};
const copyButton={addEventListener:(n,f)=>copyListeners[n]=f},status={textContent:''};
let copyWorks=true;
const elements={'market-tip':tip,'market-link-overlay':overlay,'market-link-url':field,'market-link-copy':copyButton,'market-link-close':closeButton,'market-link-status':status};
const document={getElementById:id=>elements[id],querySelectorAll:()=>[button],body:{classList:{add(){},remove(){}}},execCommand:cmd=>{assert.equal(cmd,'copy');return copyWorks;}};
vm.runInNewContext(fs.readFileSync(__dirname+'/market.js','utf8'),{
 document,
 window:{innerWidth:800,innerHeight:600,addEventListener:(n,f)=>scroll[n]=f},
 setTimeout:f=>{pending=f;return 1;},clearTimeout:()=>{pending=null;},Date,
 fetch:async url=>{requests++;assert.equal(url,'market-api.php?ref=fixture');return {ok:true,json:async()=>({name:'<img src=x onerror=alert(1)>',suggested:'10 키',sell:'11키',buy:'9키',checked:100,orders_ok:true})};}
});
(async()=>{
 listeners.mouseenter();assert.equal(tip.hidden,false);pending();await new Promise(setImmediate);
 assert.equal(tip.style.left,'186px');assert.equal(tip.style.top,'40px');
 assert(tip.textContent.includes('판매 주문 최저: 11키'));assert(tip.textContent.includes('<img src=x'));assert.equal(tip.innerHTML,undefined);
 listeners.mouseleave({relatedTarget:null});assert.equal(tip.hidden,true);
 listeners.focus();assert.equal(requests,1);assert.equal(tip.hidden,false);
 rect={left:600,right:760,top:40,bottom:240};listeners.focus();assert.equal(tip.style.left,'264px');
 let stopped=false,prevented=false;listeners.click({stopPropagation(){stopped=true;},preventDefault(){prevented=true;}});assert(stopped&&prevented);assert(tip.hidden);
 assert.equal(overlay.hidden,false);assert.equal(field.value,url);assert(field.selected);
 listeners.mouseenter();assert(tip.hidden);
 copyListeners.click();assert.equal(status.textContent,'주소를 복사했습니다.');
 copyWorks=false;copyListeners.click();assert(status.textContent.includes('Ctrl+C'));
 dialogListeners.keydown({key:'Tab',shiftKey:true,preventDefault(){}});assert.equal(document.activeElement,closeButton);
 dialogListeners.keydown({key:'Tab',shiftKey:false,preventDefault(){}});assert.equal(document.activeElement,field);
 dialogListeners.keydown({key:'Escape',preventDefault(){}});assert(overlay.hidden);assert(tip.hidden);
 listeners.keydown({key:'Escape',preventDefault(){}});assert.equal(tip.hidden,true);
 listeners.mouseenter();scroll.scroll();assert.equal(tip.hidden,true);
 console.log('PASS cached price tooltip, no navigation, copy dialog, fallback, focus trap, Escape and scroll dismissal');
})().catch(e=>{console.error(e);process.exitCode=1;});
