//! Имя монитора из EDID: производитель (три буквы, «SAM», «DEL») и модель
//! из дескриптора имени. Полный разбор (HDR, цвет) — вместе с 0.6.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Info {
    pub make: String,
    pub model: String,
}

pub fn parse(edid: &[u8]) -> Option<Info> {
    if edid.len() < 128 || edid[..8] != [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00] {
        return None;
    }
    // три буквы по 5 бит: 1 = 'A'
    let id = u16::from_be_bytes([edid[8], edid[9]]);
    let letter = |shift: u16| (b'A' - 1 + ((id >> shift) & 0x1f) as u8) as char;
    let make: String = [letter(10), letter(5), letter(0)].iter().collect();

    // четыре дескриптора по 18 байт; 0xFC — имя монитора
    let model = (0..4)
        .map(|i| &edid[54 + i * 18..72 + i * 18])
        .find(|d| d[0] == 0 && d[1] == 0 && d[3] == 0xfc)
        .map(|d| {
            let text: String = d[5..18].iter().take_while(|&&b| b != 0x0a).map(|&b| b as char).collect();
            text.trim().to_string()
        })
        .filter(|m| !m.is_empty())
        .unwrap_or_else(|| format!("{:04X}", u16::from_le_bytes([edid[10], edid[11]])));

    Some(Info { make, model })
}
