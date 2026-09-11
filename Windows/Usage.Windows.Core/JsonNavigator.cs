using System;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;

namespace Whyun.Usage.Core
{
    public static class JsonNavigator
    {
        public static object Deserialize(string json)
        {
            if (string.IsNullOrWhiteSpace(json))
            {
                throw new UsageParseException("The provider returned an empty response.");
            }

            var serializer = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };
            try
            {
                return serializer.DeserializeObject(json);
            }
            catch (Exception exception)
            {
                throw new UsageParseException("The provider returned invalid JSON: " + exception.Message);
            }
        }

        public static object Get(object root, params string[] path)
        {
            object current = root;
            foreach (string segment in path)
            {
                var dictionary = current as IDictionary<string, object>;
                object next;
                if (dictionary == null || !dictionary.TryGetValue(segment, out next))
                {
                    return null;
                }

                current = next;
            }

            return current;
        }

        public static object GetEither(object root, params string[][] paths)
        {
            foreach (string[] path in paths)
            {
                object value = Get(root, path);
                if (value != null)
                {
                    return value;
                }
            }

            return null;
        }

        public static double? Number(object value)
        {
            if (value == null)
            {
                return null;
            }

            if (value is double)
            {
                return (double)value;
            }
            if (value is decimal)
            {
                return (double)(decimal)value;
            }
            if (value is int)
            {
                return (int)value;
            }
            if (value is long)
            {
                return (long)value;
            }

            double parsed;
            return double.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Float,
                CultureInfo.InvariantCulture, out parsed) ? parsed : (double?)null;
        }

        public static string Text(object value)
        {
            return value == null ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        public static DateTimeOffset? UnixSeconds(object value)
        {
            double? seconds = Number(value);
            if (!seconds.HasValue || seconds.Value < 0)
            {
                return null;
            }

            try
            {
                return new DateTimeOffset(1970, 1, 1, 0, 0, 0, TimeSpan.Zero)
                    .AddSeconds((long)seconds.Value);
            }
            catch (ArgumentOutOfRangeException)
            {
                return null;
            }
        }

        public static DateTimeOffset? Iso8601(object value)
        {
            DateTimeOffset parsed;
            string text = Text(value);
            return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out parsed)
                ? parsed
                : (DateTimeOffset?)null;
        }
    }
}
