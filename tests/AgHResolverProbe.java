import java.net.InetAddress;
import java.util.Arrays;

/** Device read-only Android libc/netd resolver probe. No framework mutations. */
public class AgHResolverProbe {
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !args[0].matches("[a-zA-Z0-9.-]+")) throw new IllegalArgumentException("domain");
        String[] values = Arrays.stream(InetAddress.getAllByName(args[0]))
            .map(InetAddress::getHostAddress).toArray(String[]::new);
        System.out.println(Arrays.toString(values));
    }
}
