// Fixture source. Exercises string, type, field and method pool
// references so the differ has resolved symbols to report.
public class Greeter {
  private String name;

  public Greeter(String name) {
    this.name = name;
  }

  public boolean matches(String other) {
    return name.equals(other);
  }

  public String greet() {
    return "hello " + name;
  }
}
