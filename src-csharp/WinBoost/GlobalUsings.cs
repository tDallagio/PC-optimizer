// UseWindowsForms=true reemplaza el set de implicit usings: quita System.IO
// y agrega System.Drawing + System.Windows.Forms (causando colisiones con WPF).
// Este archivo repone System.IO y desambigua todos los tipos conflictivos.

global using System.IO;

global using Application    = System.Windows.Application;
global using Button         = System.Windows.Controls.Button;
global using RichTextBox    = System.Windows.Controls.RichTextBox;
global using ProgressBar    = System.Windows.Controls.ProgressBar;
global using Color          = System.Windows.Media.Color;
global using ColorConverter = System.Windows.Media.ColorConverter;
