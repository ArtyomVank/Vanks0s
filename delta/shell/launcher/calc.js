.pragma library

// Калькулятор в поиске меню: «2+2*3», «(15 - 3) / 4», «2^10», «12,5 * 3».
// Свой разбор, без eval: в поле поиска может оказаться что угодно.
// Не выражение (нет ни цифры, ни действия) — null.

function evaluate(text) {
    const src = String(text || "").trim().replace(/=$/, "").replace(/,/g, ".").replace(/[×х]/g, "*").replace(/[÷:]/g, "/");
    if (!/^[\d\s.+\-*/%^()]+$/.test(src) || !/\d/.test(src) || !/[+\-*/%^]/.test(src.replace(/^\s*-/, ""))) return null;
    let i = 0;
    const peek = () => { while (src[i] === " ") i++; return src[i]; };
    function num() {
        const c = peek();
        if (c === "(") {
            i++;
            const v = sum();
            if (peek() !== ")") throw "скобка";
            i++;
            return v;
        }
        if (c === "-") { i++; return -pow(); }
        if (c === "+") { i++; return pow(); }
        const m = /^\d*\.?\d+(e[+-]?\d+)?/i.exec(src.slice(i)) || /^\d+\.?/.exec(src.slice(i));
        if (!m) throw "число";
        i += m[0].length;
        return parseFloat(m[0]);
    }
    function pow() {
        const b = num();
        if (peek() === "^") { i++; return Math.pow(b, pow()); }
        return b;
    }
    function prod() {
        let v = pow();
        for (;;) {
            const c = peek();
            if (c === "*") { i++; v *= pow(); }
            else if (c === "/") { i++; v /= pow(); }
            else if (c === "%") { i++; v %= pow(); }
            else return v;
        }
    }
    function sum() {
        let v = prod();
        for (;;) {
            const c = peek();
            if (c === "+") { i++; v += prod(); }
            else if (c === "-") { i++; v -= prod(); }
            else return v;
        }
    }
    try {
        const v = sum();
        if (peek() !== undefined || !isFinite(v)) return null;
        return v;
    } catch (e) {
        return null;
    }
}

// Ответ для показа: без хвоста 0.30000000000000004, с пробелами в тысячах.
function format(v) {
    let s = String(Math.round(v * 1e10) / 1e10);
    if (/e/.test(s)) return s;
    const [a, b] = s.split(".");
    const neg = a[0] === "-";
    const int = (neg ? a.slice(1) : a).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    return (neg ? "−" : "") + int + (b ? "," + b : "");
}
