var JSV = (() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // node_modules/jsv/lib/jsv.js
  var require_jsv = __commonJS({
    "node_modules/jsv/lib/jsv.js"(exports) {
      var exports = exports || exports;
      var require2 = require2 || function() {
        return exports;
      };
      (function() {
        var URI = require2("./uri/uri").URI, O = {}, I2H = "0123456789abcdef".split(""), mapArray, filterArray, searchArray, JSV;
        function typeOf(o) {
          return o === void 0 ? "undefined" : o === null ? "null" : Object.prototype.toString.call(o).split(" ").pop().split("]").shift().toLowerCase();
        }
        function F() {
        }
        function createObject(proto) {
          F.prototype = proto || {};
          return new F();
        }
        function mapObject(obj, func, scope) {
          var newObj = {}, key;
          for (key in obj) {
            if (obj[key] !== O[key]) {
              newObj[key] = func.call(scope, obj[key], key, obj);
            }
          }
          return newObj;
        }
        mapArray = function(arr, func, scope) {
          var x = 0, xl = arr.length, newArr = new Array(xl);
          for (; x < xl; ++x) {
            newArr[x] = func.call(scope, arr[x], x, arr);
          }
          return newArr;
        };
        if (Array.prototype.map) {
          mapArray = function(arr, func, scope) {
            return Array.prototype.map.call(arr, func, scope);
          };
        }
        filterArray = function(arr, func, scope) {
          var x = 0, xl = arr.length, newArr = [];
          for (; x < xl; ++x) {
            if (func.call(scope, arr[x], x, arr)) {
              newArr[newArr.length] = arr[x];
            }
          }
          return newArr;
        };
        if (Array.prototype.filter) {
          filterArray = function(arr, func, scope) {
            return Array.prototype.filter.call(arr, func, scope);
          };
        }
        searchArray = function(arr, o) {
          var x = 0, xl = arr.length;
          for (; x < xl; ++x) {
            if (arr[x] === o) {
              return x;
            }
          }
          return -1;
        };
        if (Array.prototype.indexOf) {
          searchArray = function(arr, o) {
            return Array.prototype.indexOf.call(arr, o);
          };
        }
        function toArray(o) {
          return o !== void 0 && o !== null ? o instanceof Array && !o.callee ? o : typeof o.length !== "number" || o.split || o.setInterval || o.call ? [o] : Array.prototype.slice.call(o) : [];
        }
        function keys(o) {
          var result = [], key;
          switch (typeOf(o)) {
            case "object":
              for (key in o) {
                if (o[key] !== O[key]) {
                  result[result.length] = key;
                }
              }
              break;
            case "array":
              for (key = o.length - 1; key >= 0; --key) {
                result[key] = key;
              }
              break;
          }
          return result;
        }
        function pushUnique(arr, o) {
          if (searchArray(arr, o) === -1) {
            arr.push(o);
          }
          return arr;
        }
        function popFirst(arr, o) {
          var index = searchArray(arr, o);
          if (index > -1) {
            arr.splice(index, 1);
          }
          return arr;
        }
        function randomUUID() {
          return [
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            "-",
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            "-4",
            //set 4 high bits of time_high field to version
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            "-",
            I2H[Math.floor(Math.random() * 16) & 3 | 8],
            //specify 2 high bits of clock sequence
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            "-",
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)],
            I2H[Math.floor(Math.random() * 16)]
          ].join("");
        }
        function escapeURIComponent(str) {
          return encodeURIComponent(str).replace(/!/g, "%21").replace(/'/g, "%27").replace(/\(/g, "%28").replace(/\)/g, "%29").replace(/\*/g, "%2A");
        }
        function formatURI(uri) {
          if (typeof uri === "string" && uri.indexOf("#") === -1) {
            uri += "#";
          }
          return uri;
        }
        function stripInstances(o) {
          if (o instanceof JSONInstance) {
            return o.getURI();
          }
          switch (typeOf(o)) {
            case "undefined":
            case "null":
            case "boolean":
            case "number":
            case "string":
              return o;
            //do nothing
            case "object":
              return mapObject(o, stripInstances);
            case "array":
              return mapArray(o, stripInstances);
            default:
              return o.toString();
          }
        }
        function InitializationError(instance, schema, attr, message, details) {
          Error.call(this, message);
          this.uri = instance instanceof JSONInstance ? instance.getURI() : instance;
          this.schemaUri = schema instanceof JSONInstance ? schema.getURI() : schema;
          this.attribute = attr;
          this.message = message;
          this.description = message;
          this.details = details;
        }
        InitializationError.prototype = new Error();
        InitializationError.prototype.constructor = InitializationError;
        InitializationError.prototype.name = "InitializationError";
        function Report() {
          this.errors = [];
          this.validated = {};
        }
        Report.prototype.addError = function(instance, schema, attr, message, details) {
          this.errors.push({
            uri: instance instanceof JSONInstance ? instance.getURI() : instance,
            schemaUri: schema instanceof JSONInstance ? schema.getURI() : schema,
            attribute: attr,
            message,
            details: stripInstances(details)
          });
        };
        Report.prototype.registerValidation = function(uri, schemaUri) {
          if (!this.validated[uri]) {
            this.validated[uri] = [schemaUri];
          } else {
            this.validated[uri].push(schemaUri);
          }
        };
        Report.prototype.isValidatedBy = function(uri, schemaUri) {
          return !!this.validated[uri] && searchArray(this.validated[uri], schemaUri) !== -1;
        };
        function JSONInstance(env, json, uri, fd) {
          if (json instanceof JSONInstance) {
            if (typeof fd !== "string") {
              fd = json._fd;
            }
            if (typeof uri !== "string") {
              uri = json._uri;
            }
            json = json._value;
          }
          if (typeof uri !== "string") {
            uri = "urn:uuid:" + randomUUID() + "#";
          } else if (uri.indexOf(":") === -1) {
            uri = formatURI(URI.resolve("urn:uuid:" + randomUUID() + "#", uri));
          }
          this._env = env;
          this._value = json;
          this._uri = uri;
          this._fd = fd || this._env._options["defaultFragmentDelimiter"];
        }
        JSONInstance.prototype.getEnvironment = function() {
          return this._env;
        };
        JSONInstance.prototype.getType = function() {
          return typeOf(this._value);
        };
        JSONInstance.prototype.getValue = function() {
          return this._value;
        };
        JSONInstance.prototype.getURI = function() {
          return this._uri;
        };
        JSONInstance.prototype.resolveURI = function(uri) {
          return formatURI(URI.resolve(this._uri, uri));
        };
        JSONInstance.prototype.getPropertyNames = function() {
          return keys(this._value);
        };
        JSONInstance.prototype.getProperty = function(key) {
          var value = this._value ? this._value[key] : void 0;
          if (value instanceof JSONInstance) {
            return value;
          }
          return new JSONInstance(this._env, value, this._uri + this._fd + escapeURIComponent(key), this._fd);
        };
        JSONInstance.prototype.getProperties = function() {
          var type = typeOf(this._value), self = this;
          if (type === "object") {
            return mapObject(this._value, function(value, key) {
              if (value instanceof JSONInstance) {
                return value;
              }
              return new JSONInstance(self._env, value, self._uri + self._fd + escapeURIComponent(key), self._fd);
            });
          } else if (type === "array") {
            return mapArray(this._value, function(value, key) {
              if (value instanceof JSONInstance) {
                return value;
              }
              return new JSONInstance(self._env, value, self._uri + self._fd + escapeURIComponent(key), self._fd);
            });
          }
        };
        JSONInstance.prototype.getValueOfProperty = function(key) {
          if (this._value) {
            if (this._value[key] instanceof JSONInstance) {
              return this._value[key]._value;
            }
            return this._value[key];
          }
        };
        JSONInstance.prototype.equals = function(instance) {
          if (instance instanceof JSONInstance) {
            return this._value === instance._value;
          }
          return this._value === instance;
        };
        function clone(obj, deep) {
          var newObj, x;
          if (obj instanceof JSONInstance) {
            obj = obj.getValue();
          }
          switch (typeOf(obj)) {
            case "object":
              if (deep) {
                newObj = {};
                for (x in obj) {
                  if (obj[x] !== O[x]) {
                    newObj[x] = clone(obj[x], deep);
                  }
                }
                return newObj;
              } else {
                return createObject(obj);
              }
              break;
            case "array":
              if (deep) {
                newObj = new Array(obj.length);
                x = obj.length;
                while (--x >= 0) {
                  newObj[x] = clone(obj[x], deep);
                }
                return newObj;
              } else {
                return Array.prototype.slice.call(obj);
              }
              break;
            default:
              return obj;
          }
        }
        function JSONSchema(env, json, uri, schema) {
          var fr;
          JSONInstance.call(this, env, json, uri);
          if (schema === true) {
            this._schema = this;
          } else if (json instanceof JSONSchema && !(schema instanceof JSONSchema)) {
            this._schema = json._schema;
          } else {
            this._schema = schema instanceof JSONSchema ? schema : this._env.getDefaultSchema() || this._env.createEmptySchema();
          }
          fr = this._schema.getValueOfProperty("fragmentResolution");
          if (fr === "dot-delimited") {
            this._fd = ".";
          } else if (fr === "slash-delimited") {
            this._fd = "/";
          }
          return this.rebuild();
        }
        JSONSchema.prototype = createObject(JSONInstance.prototype);
        JSONSchema.prototype.getSchema = function() {
          var uri = this._refs && this._refs["describedby"], newSchema;
          if (uri) {
            newSchema = uri && this._env.findSchema(uri);
            if (newSchema) {
              if (!newSchema.equals(this._schema)) {
                this._schema = newSchema;
                this.rebuild();
              }
            } else if (this._env._options["enforceReferences"]) {
              throw new InitializationError(this, this._schema, "{describedby}", "Unknown schema reference", uri);
            }
          }
          return this._schema;
        };
        JSONSchema.prototype.getAttribute = function(key, arg) {
          var schemaProperty, parser, property, result, schema = this.getSchema();
          if (!arg && this._attributes && this._attributes.hasOwnProperty(key)) {
            return this._attributes[key];
          }
          schemaProperty = schema.getProperty("properties").getProperty(key);
          parser = schemaProperty.getValueOfProperty("parser");
          property = this.getProperty(key);
          if (typeof parser === "function") {
            result = parser(property, schemaProperty, arg);
            if (!arg && this._attributes) {
              this._attributes[key] = result;
            }
            return result;
          }
          return property.getValue();
        };
        JSONSchema.prototype.getAttributes = function() {
          var properties, schemaProperties, key, schemaProperty, parser, schema = this.getSchema();
          if (!this._attributes && this.getType() === "object") {
            properties = this.getProperties();
            schemaProperties = schema.getProperty("properties");
            this._attributes = {};
            for (key in properties) {
              if (properties[key] !== O[key]) {
                schemaProperty = schemaProperties && schemaProperties.getProperty(key);
                parser = schemaProperty && schemaProperty.getValueOfProperty("parser");
                if (typeof parser === "function") {
                  this._attributes[key] = parser(properties[key], schemaProperty);
                } else {
                  this._attributes[key] = properties[key].getValue();
                }
              }
            }
          }
          return clone(this._attributes, false);
        };
        JSONSchema.prototype.getLink = function(rel, instance) {
          var schemaLinks = this.getAttribute("links", [rel, instance]);
          if (schemaLinks && schemaLinks.length && schemaLinks[schemaLinks.length - 1]) {
            return schemaLinks[schemaLinks.length - 1];
          }
        };
        JSONSchema.prototype.validate = function(instance, report, parent, parentSchema, name) {
          var schemaSchema = this.getSchema(), validator = schemaSchema.getValueOfProperty("validator");
          if (!(instance instanceof JSONInstance)) {
            instance = this.getEnvironment().createInstance(instance);
          }
          if (!(report instanceof Report)) {
            report = new Report();
          }
          if (this._env._options["validateReferences"] && this._refs) {
            if (this._refs["describedby"] && !this._env.findSchema(this._refs["describedby"])) {
              report.addError(this, this._schema, "{describedby}", "Unknown schema reference", this._refs["describedby"]);
            }
            if (this._refs["full"] && !this._env.findSchema(this._refs["full"])) {
              report.addError(this, this._schema, "{full}", "Unknown schema reference", this._refs["full"]);
            }
          }
          if (typeof validator === "function" && !report.isValidatedBy(instance.getURI(), this.getURI())) {
            report.registerValidation(instance.getURI(), this.getURI());
            validator(instance, this, schemaSchema, report, parent, parentSchema, name);
          }
          return report;
        };
        function createFullLookupWrapper(func) {
          return (
            /** @inner */
            function fullLookupWrapper() {
              var scope = this, stack = [], uri = scope._refs && scope._refs["full"], schema;
              while (uri) {
                schema = scope._env.findSchema(uri);
                if (schema) {
                  if (schema._value === scope._value) {
                    break;
                  }
                  scope = schema;
                  stack.push(uri);
                  uri = scope._refs && scope._refs["full"];
                  if (stack.indexOf(uri) > -1) {
                    break;
                  }
                } else if (scope._env._options["enforceReferences"]) {
                  throw new InitializationError(scope, scope._schema, "{full}", "Unknown schema reference", uri);
                } else {
                  uri = null;
                }
              }
              return func.apply(scope, arguments);
            }
          );
        }
        (function() {
          var key;
          for (key in JSONSchema.prototype) {
            if (JSONSchema.prototype[key] !== O[key] && typeOf(JSONSchema.prototype[key]) === "function") {
              JSONSchema.prototype[key] = createFullLookupWrapper(JSONSchema.prototype[key]);
            }
          }
        })();
        JSONSchema.prototype.rebuild = function() {
          var instance = this, initializer = instance.getSchema().getValueOfProperty("initializer");
          instance._refs = null;
          instance._attributes = null;
          if (typeof initializer === "function") {
            instance = initializer(instance);
          }
          instance._env._schemas[instance._uri] = instance;
          instance.getAttributes();
          return instance;
        };
        JSONSchema.prototype.setReference = function(name, uri) {
          if (!this._refs) {
            this._refs = {};
          }
          this._refs[name] = this.resolveURI(uri);
        };
        JSONSchema.prototype.getReference = function(name) {
          return this._refs && this._refs[name];
        };
        function inherits(base, extra, extension) {
          var baseType = typeOf(base), extraType = typeOf(extra), child, x;
          if (extraType === "undefined") {
            return clone(base, true);
          } else if (baseType === "undefined" || extraType !== baseType) {
            return clone(extra, true);
          } else if (extraType === "object") {
            if (base instanceof JSONSchema) {
              base = base.getAttributes();
            }
            if (extra instanceof JSONSchema) {
              extra = extra.getAttributes();
              if (extra["extends"] && extension && extra["extends"] instanceof JSONSchema) {
                extra["extends"] = [extra["extends"]];
              }
            }
            child = clone(base, true);
            for (x in extra) {
              if (extra[x] !== O[x]) {
                child[x] = inherits(base[x], extra[x], extension);
              }
            }
            return child;
          } else {
            return clone(extra, true);
          }
        }
        function Environment() {
          this._id = randomUUID();
          this._schemas = {};
          this._options = {};
          this.createSchema({}, true, "urn:jsv:empty-schema#");
        }
        Environment.prototype.clone = function() {
          var env = new Environment();
          env._schemas = createObject(this._schemas);
          env._options = createObject(this._options);
          return env;
        };
        Environment.prototype.createInstance = function(data, uri) {
          uri = formatURI(uri);
          if (data instanceof JSONInstance && (!uri || data.getURI() === uri)) {
            return data;
          }
          return new JSONInstance(this, data, uri);
        };
        Environment.prototype.createSchema = function(data, schema, uri) {
          uri = formatURI(uri);
          if (data instanceof JSONSchema && (!uri || data._uri === uri) && (!schema || data.getSchema().equals(schema))) {
            return data;
          }
          return new JSONSchema(this, data, uri, schema);
        };
        Environment.prototype.createEmptySchema = function() {
          return this._schemas["urn:jsv:empty-schema#"];
        };
        Environment.prototype.findSchema = function(uri) {
          return this._schemas[formatURI(uri)];
        };
        Environment.prototype.setOption = function(name, value) {
          this._options[name] = value;
        };
        Environment.prototype.getOption = function(name) {
          return this._options[name];
        };
        Environment.prototype.setDefaultFragmentDelimiter = function(fd) {
          if (typeof fd === "string" && fd.length > 0) {
            this._options["defaultFragmentDelimiter"] = fd;
          }
        };
        Environment.prototype.getDefaultFragmentDelimiter = function() {
          return this._options["defaultFragmentDelimiter"];
        };
        Environment.prototype.setDefaultSchemaURI = function(uri) {
          if (typeof uri === "string") {
            this._options["defaultSchemaURI"] = formatURI(uri);
          }
        };
        Environment.prototype.getDefaultSchema = function() {
          return this.findSchema(this._options["defaultSchemaURI"]);
        };
        Environment.prototype.validate = function(instanceJSON, schemaJSON) {
          var instance, schema, schemaSchema, report = new Report();
          try {
            instance = this.createInstance(instanceJSON);
            report.instance = instance;
          } catch (e) {
            report.addError(e.uri, e.schemaUri, e.attribute, e.message, e.details);
          }
          try {
            schema = this.createSchema(schemaJSON);
            report.schema = schema;
            schemaSchema = schema.getSchema();
            report.schemaSchema = schemaSchema;
          } catch (f) {
            report.addError(f.uri, f.schemaUri, f.attribute, f.message, f.details);
          }
          if (schemaSchema) {
            schemaSchema.validate(schema, report);
          }
          if (report.errors.length) {
            return report;
          }
          return schema.validate(instance, report);
        };
        Environment.prototype._checkForInvalidInstances = function(stackSize, schemaURI) {
          var result = [], stack = [
            [schemaURI, this._schemas[schemaURI]]
          ], counter = 0, item, uri, instance, properties, key;
          while (counter++ < stackSize && stack.length) {
            item = stack.shift();
            uri = item[0];
            instance = item[1];
            if (instance instanceof JSONSchema) {
              if (this._schemas[instance._uri] !== instance) {
                result.push("Instance " + uri + " does not match " + instance._uri);
              } else {
                properties = instance.getAttributes();
                for (key in properties) {
                  if (properties[key] !== O[key]) {
                    stack.push([uri + "/" + escapeURIComponent(key), properties[key]]);
                  }
                }
              }
            } else if (typeOf(instance) === "object") {
              properties = instance;
              for (key in properties) {
                if (properties.hasOwnProperty(key)) {
                  stack.push([uri + "/" + escapeURIComponent(key), properties[key]]);
                }
              }
            } else if (typeOf(instance) === "array") {
              properties = instance;
              for (key = 0; key < properties.length; ++key) {
                stack.push([uri + "/" + escapeURIComponent(key), properties[key]]);
              }
            }
          }
          return result.length ? result : counter;
        };
        JSV = {
          _environments: {},
          _defaultEnvironmentID: "",
          /**
           * Returns if the provide value is an instance of {@link JSONInstance}.
           * 
           * @param o The value to test
           * @returns {Boolean} If the provide value is an instance of {@link JSONInstance}
           */
          isJSONInstance: function(o) {
            return o instanceof JSONInstance;
          },
          /**
           * Returns if the provide value is an instance of {@link JSONSchema}.
           * 
           * @param o The value to test
           * @returns {Boolean} If the provide value is an instance of {@link JSONSchema}
           */
          isJSONSchema: function(o) {
            return o instanceof JSONSchema;
          },
          /**
           * Creates and returns a new {@link Environment} that is a clone of the environment registered with the provided ID.
           * If no environment ID is provided, the default environment is cloned.
           * 
           * @param {String} [id] The ID of the environment to clone. If <code>undefined</code>, the default environment ID is used.
           * @returns {Environment} A newly cloned {@link Environment}
           * @throws {Error} If there is no environment registered with the provided ID
           */
          createEnvironment: function(id) {
            id = id || this._defaultEnvironmentID;
            if (!this._environments[id]) {
              throw new Error("Unknown Environment ID");
            }
            return this._environments[id].clone();
          },
          Environment,
          /**
           * Registers the provided {@link Environment} with the provided ID.
           * 
           * @param {String} id The ID of the environment
           * @param {Environment} env The environment to register
           */
          registerEnvironment: function(id, env) {
            id = id || (env || 0)._id;
            if (id && !this._environments[id] && env instanceof Environment) {
              env._id = id;
              this._environments[id] = env;
            }
          },
          /**
           * Sets which registered ID is the default environment.
           * 
           * @param {String} id The ID of the registered environment that is default
           * @throws {Error} If there is no registered environment with the provided ID
           */
          setDefaultEnvironmentID: function(id) {
            if (typeof id === "string") {
              if (!this._environments[id]) {
                throw new Error("Unknown Environment ID");
              }
              this._defaultEnvironmentID = id;
            }
          },
          /**
           * Returns the ID of the default environment.
           * 
           * @returns {String} The ID of the default environment
           */
          getDefaultEnvironmentID: function() {
            return this._defaultEnvironmentID;
          },
          //
          // Utility Functions
          //
          /**
           * Returns the name of the type of the provided value.
           *
           * @event //utility
           * @param {Any} o The value to determine the type of
           * @returns {String} The name of the type of the value
           */
          typeOf,
          /**
           * Return a new object that inherits all of the properties of the provided object.
           *
           * @event //utility
           * @param {Object} proto The prototype of the new object
           * @returns {Object} A new object that inherits all of the properties of the provided object
           */
          createObject,
          /**
           * Returns a new object with each property transformed by the iterator.
           *
           * @event //utility
           * @param {Object} obj The object to transform
           * @param {Function} iterator A function that returns the new value of the provided property
           * @param {Object} [scope] The value of <code>this</code> in the iterator
           * @returns {Object} A new object with each property transformed
           */
          mapObject,
          /**
           * Returns a new array with each item transformed by the iterator.
           * 
           * @event //utility
           * @param {Array} arr The array to transform
           * @param {Function} iterator A function that returns the new value of the provided item
           * @param {Object} scope The value of <code>this</code> in the iterator
           * @returns {Array} A new array with each item transformed
           */
          mapArray,
          /**
           * Returns a new array that only contains the items allowed by the iterator.
           *
           * @event //utility
           * @param {Array} arr The array to filter
           * @param {Function} iterator The function that returns true if the provided property should be added to the array
           * @param {Object} scope The value of <code>this</code> within the iterator
           * @returns {Array} A new array that contains the items allowed by the iterator
           */
          filterArray,
          /**
           * Returns the first index in the array that the provided item is located at.
           *
           * @event //utility
           * @param {Array} arr The array to search
           * @param {Any} o The item being searched for
           * @returns {Number} The index of the item in the array, or <code>-1</code> if not found
           */
          searchArray,
          /**
           * Returns an array representation of a value.
           * <ul>
           * <li>For array-like objects, the value will be casted as an Array type.</li>
           * <li>If an array is provided, the function will simply return the same array.</li>
           * <li>For a null or undefined value, the result will be an empty Array.</li>
           * <li>For all other values, the value will be the first element in a new Array. </li>
           * </ul>
           *
           * @event //utility
           * @param {Any} o The value to convert into an array
           * @returns {Array} The value as an array
           */
          toArray,
          /**
           * Returns an array of the names of all properties of an object.
           * 
           * @event //utility
           * @param {Object|Array} o The object in question
           * @returns {Array} The names of all properties
           */
          keys,
          /**
           * Mutates the array by pushing the provided value onto the array only if it is not already there.
           *
           * @event //utility
           * @param {Array} arr The array to modify
           * @param {Any} o The object to add to the array if it is not already there
           * @returns {Array} The provided array for chaining
           */
          pushUnique,
          /**
           * Mutates the array by removing the first item that matches the provided value in the array.
           *
           * @event //utility
           * @param {Array} arr The array to modify
           * @param {Any} o The object to remove from the array
           * @returns {Array} The provided array for chaining
           */
          popFirst,
          /**
           * Creates a copy of the target object.
           * <p>
           * This method will create a new instance of the target, and then mixin the properties of the target.
           * If <code>deep</code> is <code>true</code>, then each property will be cloned before mixin.
           * </p>
           * <p><b>Warning</b>: This is not a generic clone function, as it will only properly clone objects and arrays.</p>
           * 
           * @event //utility
           * @param {Any} o The value to clone 
           * @param {Boolean} [deep=false] If each property should be recursively cloned
           * @returns A cloned copy of the provided value
           */
          clone,
          /**
           * Generates a pseudo-random UUID.
           * 
           * @event //utility
           * @returns {String} A new universally unique ID
           */
          randomUUID,
          /**
           * Properly escapes a URI component for embedding into a URI string.
           * 
           * @event //utility
           * @param {String} str The URI component to escape
           * @returns {String} The escaped URI component
           */
          escapeURIComponent,
          /**
           * Returns a URI that is formated for JSV. Currently, this only ensures that the URI ends with a hash tag (<code>#</code>).
           * 
           * @event //utility
           * @param {String} uri The URI to format
           * @returns {String} The URI formatted for JSV
           */
          formatURI,
          /**
           * Merges two schemas/instance together.
           * 
           * @event //utility
           * @param {JSONSchema|Any} base The old value to merge
           * @param {JSONSchema|Any} extra The new value to merge
           * @param {Boolean} extension If the merge is a JSON Schema extension
           * @return {Any} The modified base value
           */
          inherits,
          /**
           * @private
           * @event //utility
           */
          InitializationError
        };
        this.JSV = JSV;
        exports.JSV = JSV;
        require2("./environments");
      })();
    }
  });
  return require_jsv();
})();
