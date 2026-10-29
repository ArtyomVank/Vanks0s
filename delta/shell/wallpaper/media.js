.pragma library

// Общие помощники для обоев и выбора обоев.

const IMAGE = ["jpg", "jpeg", "png", "webp", "bmp", "avif", "jxl", "tif", "tiff"];
const VIDEO = ["mp4", "webm", "mkv", "mov", "m4v", "avi"];

function ext(path) {
    const name = String(path || "").split("/").pop();
    const i = name.lastIndexOf(".");
    return i > 0 ? name.slice(i + 1).toLowerCase() : "";
}

function isVideo(path) { return VIDEO.indexOf(ext(path)) !== -1; }
function isImage(path) { return IMAGE.indexOf(ext(path)) !== -1; }

// «#», «?» и пробелы в именах файлов ломают простое "file://" + путь
function fileUrl(path) {
    if (!path) return "";
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}

function baseName(path) {
    const name = String(path || "").split("/").pop();
    const i = name.lastIndexOf(".");
    return i > 0 ? name.slice(0, i) : name;
}

// ~/… вместо /home/<имя>/…
function pretty(path, home) {
    if (home && path && (path === home || path.startsWith(home + "/"))) return "~" + path.slice(home.length);
    return path || "";
}
