//! Имя монитора из EDID: производитель (три буквы, «SAM», «DEL») и модель
//! из дескриптора имени, а также что монитор заявляет про HDR.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Info {
    pub make: String,
    pub model: String,
    pub serial: String,
}

/// Полное имя производителя, как его показывает Hyprland: описание монитора
/// должно совпасть с сохранённым в настройках Delta. Нет в списке — три буквы.
fn vendor_name(code: &str) -> Option<String> {
    let table = std::fs::read_to_string("/usr/share/hwdata/pnp.ids").ok()?;
    table.lines().find_map(|l| l.strip_prefix(code)?.strip_prefix('\t').map(|n| n.trim().to_string()))
}

pub fn parse(edid: &[u8]) -> Option<Info> {
    if edid.len() < 128 || edid[..8] != [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00] {
        return None;
    }
    // три буквы по 5 бит: 1 = 'A'
    let id = u16::from_be_bytes([edid[8], edid[9]]);
    let letter = |shift: u16| (b'A' - 1 + ((id >> shift) & 0x1f) as u8) as char;
    let make: String = [letter(10), letter(5), letter(0)].iter().collect();

    let make = vendor_name(&make).unwrap_or(make);

    // четыре дескриптора по 18 байт; 0xFC — имя монитора, 0xFF — серийный номер
    let text = |tag: u8| {
        (0..4)
            .map(|i| &edid[54 + i * 18..72 + i * 18])
            .find(|d| d[0] == 0 && d[1] == 0 && d[3] == tag)
            .map(|d| {
                let text: String = d[5..18].iter().take_while(|&&b| b != 0x0a).map(|&b| b as char).collect();
                text.trim().to_string()
            })
            .filter(|t| !t.is_empty())
    };
    let model = text(0xfc).unwrap_or_else(|| format!("0x{:04X}", u16::from_le_bytes([edid[10], edid[11]])));
    let number = u32::from_le_bytes([edid[12], edid[13], edid[14], edid[15]]);
    let serial = text(0xff).unwrap_or_else(|| if number != 0 { format!("0x{number:08X}") } else { String::new() });

    Some(Info { make, model, serial })
}

/// Что монитор заявляет про HDR в расширении CTA-861.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Hdr {
    /// умеет SMPTE ST 2084 (PQ)
    pub pq: bool,
    /// яркость, кд/м²; 0 — не заявлена
    pub max_nits: f32,
    pub avg_nits: f32,
    pub min_nits: f32,
}

pub fn hdr(edid: &[u8]) -> Hdr {
    let mut out = Hdr::default();
    for block in edid.chunks_exact(128).skip(1).filter(|b| b[0] == 0x02) {
        // блоки данных лежат с 4-го байта до смещения первого описания таймингов
        let end = (block[2] as usize).clamp(4, 127);
        let mut i = 4;
        while i < end {
            let (tag, len) = (block[i] >> 5, (block[i] & 0x1f) as usize);
            let data = &block[(i + 1).min(end)..(i + 1 + len).min(end)];
            match (tag, data.first()) {
                // статические метаданные HDR: 2-й бит — ST 2084
                (7, Some(6)) if data.len() >= 3 => {
                    out.pq = data[1] & 0x04 != 0;
                    let nits = |cv: u8| 50.0 * 2f32.powf(f32::from(cv) / 32.0);
                    if let Some(&cv) = data.get(3).filter(|cv| **cv > 0) {
                        out.max_nits = nits(cv);
                    }
                    if let Some(&cv) = data.get(4).filter(|cv| **cv > 0) {
                        out.avg_nits = nits(cv);
                    }
                    if let Some(&cv) = data.get(5) {
                        out.min_nits = out.max_nits * (f32::from(cv) / 255.0).powi(2) / 100.0;
                    }
                }
                _ => {}
            }
            i += 1 + len;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn edid(descriptors: &[(u8, &str)], number: u32) -> Vec<u8> {
        let mut e = vec![0u8; 128];
        e[..8].copy_from_slice(&[0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]);
        // «MKG» — такого производителя нет в списках, имя остаётся тремя буквами
        let id = ((b'M' - b'A' + 1) as u16) << 10 | ((b'K' - b'A' + 1) as u16) << 5 | (b'G' - b'A' + 1) as u16;
        e[8..10].copy_from_slice(&id.to_be_bytes());
        e[10..12].copy_from_slice(&0x1234u16.to_le_bytes());
        e[12..16].copy_from_slice(&number.to_le_bytes());
        for (i, (tag, text)) in descriptors.iter().enumerate() {
            let d = &mut e[54 + i * 18..72 + i * 18];
            d[3] = *tag;
            d[5..5 + text.len()].copy_from_slice(text.as_bytes());
            d[5 + text.len()] = 0x0a;
        }
        e
    }

    #[test]
    fn names() {
        let i = parse(&edid(&[(0xff, "005TR9QT8YU"), (0xfc, "MJF24F200")], 7)).unwrap();
        assert_eq!((i.make.as_str(), i.model.as_str(), i.serial.as_str()), ("MKG", "MJF24F200", "005TR9QT8YU"));
        let i = parse(&edid(&[], 7)).unwrap();
        assert_eq!((i.model.as_str(), i.serial.as_str()), ("0x1234", "0x00000007"));
        assert_eq!(parse(&edid(&[], 0)).unwrap().serial, "");
        assert!(parse(&[0; 64]).is_none());
    }

    #[test]
    fn hdr_block() {
        let mut edid = vec![0u8; 256];
        edid[128] = 0x02;
        edid[130] = 40;
        // чужой блок, затем статические метаданные: SDR + PQ, тип 1, 0x61 → 408,8 кд/м²
        edid[132..136].copy_from_slice(&[0xe3, 5, 0xc0, 0x00]);
        edid[136..143].copy_from_slice(&[0xe6, 6, 0x05, 0x01, 0x61, 0x61, 0x07]);
        let h = hdr(&edid);
        assert!(h.pq);
        assert!((h.max_nits - 408.76).abs() < 0.1, "{}", h.max_nits);
        assert!((h.min_nits - 0.00308).abs() < 0.001, "{}", h.min_nits);
        assert_eq!(hdr(&edid[..128]), Hdr::default());
    }
}
