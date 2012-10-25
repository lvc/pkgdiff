function sort(el, status)
{ 
    var col_sort = el.innerHTML;
    var tr = el.parentNode;
    var table = tr.parentNode;
    var td, col_sort_num;
    for (var i=0; (td = tr.getElementsByTagName('th').item(i)); i++)
    {
        if(td.innerHTML == col_sort)
        {
            col_sort_num = i;
            if(td.prevsort == 'y') {
                el.up = Number(!el.up);
            }
            else if(td.prevsort == 'n') {
                td.prevsort = 'y';
                el.up = 0;
            }
            else
            {
                if(col_sort_num==0)
                { // already sorted
                    td.prevsort = 'n';
                    el.up = 1;
                }
                else if(col_sort_num==2)
                { // delta
                    td.prevsort = 'n';
                    el.up = 1;
                }
                else
                {
                    td.prevsort = 'y';
                    el.up = 0;
                }
            }
        }
        else
        {
            if(td.prevsort == 'y') {
                td.prevsort = 'n';
            }
        }
    }
    
    var a = new Array();
    for(var i=1; i < table.rows.length; i++)
    {
        var cols = table.rows[i].getElementsByTagName('td');
        if(cols.item(status)==null)
        { // double status
            a[i-2][2] = table.rows[i];
        }
        else
        {
            a[i-1] = new Array();
            var indent = cols.item(col_sort_num).innerHTML;
            if(indent=='') indent='0';
            if(indent.substr(indent.length-1, 1)=="%")
            { // delta
                indent = indent.substr(0, indent.length-1)*100;
            }
            a[i-1][0] = indent;
            a[i-1][1] = table.rows[i];
            a[i-1][2] = null;
        }
    }
    
    // sort table
    a.sort(sort_array);
    if(el.up) a.reverse();
    
    // draw table
    for(var i in a)
    {
        table.appendChild(a[i][1]);
        if(a[i][2]!=null) {
            table.appendChild(a[i][2]);
        }
    }
}

function sort_array(a,b)
{
    if(a[0] == b[0]) return 0;
    if(a[0] > b[0]) return 1;
    return -1;
}