// Fixture source. Exercises the pseudo-instruction payloads, a packed switch,
// a sparse switch and a fill-array-data block, plus a string constant so
// redaction has something to redact.
public class Payloads {
  public int packed(int i) {
    switch (i) {
      case 0: return 10;
      case 1: return 11;
      case 2: return 12;
      case 3: return 13;
      default: return -1;
    }
  }

  public int sparse(int i) {
    switch (i) {
      case 1: return 1;
      case 900: return 2;
      case 70000: return 3;
      default: return -1;
    }
  }

  public int[] filled() {
    return new int[] {7, 8, 9, 10, 11, 12, 13, 14};
  }

  public String secret() {
    return "token-abc,123";
  }
}
