using System;
using System.IO;
using System.Net.Sockets;
using System.Text;

public sealed class HKLiveSplitClient : IDisposable
{
    readonly TcpClient client;
    readonly StreamReader reader;
    readonly StreamWriter writer;
    public HKLiveSplitClient(int port)
    {
        client = new TcpClient();
        try
        {
            if (!client.ConnectAsync("127.0.0.1", port).Wait(2000))
                throw new IOException("Nie mozna polaczyc sie z LiveSplitem. Wlacz Control > Start TCP Server.");
            client.NoDelay = true;
            client.ReceiveTimeout = 2000;
            client.SendTimeout = 2000;
            NetworkStream stream = client.GetStream();
            reader = new StreamReader(stream, Encoding.UTF8);
            writer = new StreamWriter(stream, new UTF8Encoding(false));
            writer.NewLine = "\n";
            writer.AutoFlush = true;
        }
        catch { client.Close(); throw; }
    }
    public void Send(string command)
    {
        if (command.IndexOf('\n') >= 0 || command.IndexOf('\r') >= 0)
            throw new ArgumentException("Polecenie zawiera nowa linie.");
        writer.WriteLine(command);
    }
    public string Query(string command)
    {
        Send(command);
        string result = reader.ReadLine();
        if (result == null) throw new IOException("LiveSplit zamknal polaczenie.");
        return result.Trim();
    }
    public void Dispose() { client.Close(); }
}
