function call_property(item, property){
  if(property in item){
    item[property];
    if(item[property] instanceof Function){
      return item[property]();
    }else{
      return item[property];
    }

  }else if(Symbol.for(property) in item){
    let prop = Symbol.for(property)
    if(item[prop] instanceof Function){
      return item[prop]();
    }else{
      return item[prop];
    }
  }

  throw new Error(`Property ${property} not found in ${item}`);
}

function is_instance_of(value, type){
  return value instanceof type;
}

export {
  call_property,
  is_instance_of
};
