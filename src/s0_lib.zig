pub const Source = struct {
    from: u32,
    till: u32,

    const Self = @This();

    pub fn to_str(self: Self, input: []const u8) []const u8 {
        return input[self.from..self.till];
    }
};

// https://github.com/CrowdHailer/eyg-lang/tree/main/spec
// The examples on the very right are my research from pressing ? to show the AST the documentation page

// variable                           {"0": "v", "l": label}
// lambda(label, body)                {"0": "f", "l": label, "b": expr}            // (x, y) -> !int_add(x,y): call(lambda(x), call(lambda(y), ...))
// apply(function, arg)               {"0": "a", "f": expr, "a": expr}             // aka. call
// let(label, value, then)            {"0": "a", "l": label, "v": expr, "t": expr} //
// binary(value)                      {"0": "x", "v": bytes}                       // JSON
// integer(value)                     {"0": "i", "v": integer}                     // JSON
// string(value)                      {"0": "s", "v": string}                      // JSON
// tail                               {"0": "ta"}                                  // think lisp: call(call(cons, ...), tail)
// cons                               {"0": "c"}                                   // think lisp: call(..., tail)
// vacant(comment)                    {"0": "z", "c": string}                      // comments
// empty                              {"0": "u"}                                   // aka. {}
// extend(label)                      {"0": "e", "l": label}                       // { name: "" }: call(extend(name), "")
// select(label)                      {"0": "g", "l": label}                       // parent.label: call(select("label"), parent)
// overwrite(label)                   {"0": "o", "l": label}                       // { height: 100, ..bob}: call(overwrite(height), 100)
// tag(label)                         {"0": "t", "l": label}                       // Tag Union, Err(""): call(tag(Err), "")j
// case(label)                        {"0": "m", "l": label}                       // match ? { ok(value) -> value }: call(case(Ok), lambda(value, value))
// nocases                            {"0": "n"}                                   // end of match
// perform(label)                     {"0": "p", "l": label}                       // call(perform(label), body)
// handle(label)                      {"0": "h", "l": label}                       // call(handle(label), function())
// shallow(label)                     {"0": "hs", "l": label}                      // ?
// builtin(label)                     {"0": "b", "l": label}                       // !int_add(1, 2): call(call(builtin(int_add), 1), 2)
// reference(identifier)              {"0": "#", "l": cid}                         // ?
// release(project,release,identifer) {"0": "#", "p": string, "r": integer, "l": cid} // @standard:1

//lambda(ident, expr)
//apply(label, expr)
//let(label, expr that returns, expr)
//cons(expr)
//extend(name, expr)
//overwrite(label, expr)
//tag(label, expr):  tag(label, empty) is just a enum
//case(label, expr)
//perform(label, expr)
//handle(label, expr)

//variable(ident)
//integer([]
//string
//tail
// ?? vacant
//empty
//select(label, expr)
//nocases

// ?? binary






////////////////////////////////////////////////////////////////////////////////
// let
// variables
// lambda
// list (all must e same type)
// map
// map with elipsis
// taged unions

